require_dependency "user_service/application_controller"

module UserService
  class MembersController < UserService::ApplicationController
    before_action :authenticate_user

    def serializer
      UserService::MemberSerializer.new(member: @member,
                                        members: @members,
                                        seller_id: current_user.seller_id)
    end

    def index
      @members = ::User.where("? = any(seller_ids)", current_user.seller_id).
        where.not(seller_id: nil, confirmed_at: nil)
      render json: serializer.index
    end

    def log_user_event!(user, note)
      SharedResources::RemoteEvent.generate_token current_user
      SharedResources::RemoteEvent.create_event(user.id, 'User', current_user&.id, 'Event::User', note)
    end

    def invite_existing_seller seller_id
      if @user.seller_ids.include? seller_id
        raise SharedModules::AlertError.new(@user.confirmed? ?
          'This user is already member of your team' : 'This user is already invited')
      elsif !@user.is_seller?
        raise SharedModules::AlertError.new('This user has registered with a non-supplier account.')
      elsif !@user.confirmed?
        raise SharedModules::AlertError.new('This address is not confirmed yet.')
      else
        SharedResources::RemoteNotification.create_notification(
          unifier: 'invite_' + @user.id.to_s + '_to_' + seller_id.to_s,
          recipients: [@user.id],
          subject: "Your are invited by #{current_user.email} to join their team",
          body: "By accepting this invitation you will be able to make changes to their company account and profile. If you are already member of any team, you will not loose your access rights to your current team.",
          fa_icon: 'user-shield',
          actions: [
            {
              key: 'accept',
              caption: 'Accept',
              resource: 'remote_user',
              method: 'add_to_team',
              params: [@user.id, seller_id],
              success_message: 'invitation_accepted',
            },
            {
              key: 'decline',
              caption: 'Decline',
              button_class: 'button-secondary',
              success_message: 'invitation_declined',
            },
          ]
        )
        @member = @user
        log_user_event!(@member, "User invited to join supplier: " + seller_id.to_s)
        render json: serializer.show, status: :created
      end
    end

    def create
      raise SharedModules::MethodNotAllowed unless current_user.is_seller? && current_user.seller_id
      raise SharedModules::MethodNotAllowed unless current_user.can?(current_user.seller_id, :owner)

      @user = ::User.find_by(email: member_params[:email])
      if @user
        invite_existing_seller current_user.seller_id
        return
      end

      @member = ::User.new(member_params)
      @member.seller_id = current_user.seller_id
      @member.seller_ids = [current_user.seller_id]
      @member.has_password = false
      @member.roles = ['seller']
      @member.password = @member.password_confirmation = SecureRandom.hex(32)
      @member.skip_confirmation_notification!

      if @member.save
        UserService::SyncTendersJob.perform_later @member.id
        mailer = SellerInvitationMailer.with(user: @member)
        mailer.seller_invitation_email.deliver_later
        log_user_event!(@member, "User created by invite to join supplier: " + @member.seller_id.to_s)
        render json: serializer.show, status: :created
      else
        render json: { errors: [
          @member.errors&.messages&.map{|k,v|
            [k, k.to_s + ' ' + v.first.to_s]
          }.to_h
        ] }, status: :unprocessable_entity
      end
    end

    private

    def member_params
      params.require(:member).permit(:email)
    end
  end
end
