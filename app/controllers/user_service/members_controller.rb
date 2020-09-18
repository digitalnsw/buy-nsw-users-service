require_dependency "user_service/application_controller"

module UserService
  class MembersController < UserService::ApplicationController
    before_action :authenticate_user

    def serializer
      UserService::MemberSerializer.new(member: @member, members: @members)
    end

    def index
      @members = ::User.where("? = any(seller_ids)", current_user.seller_id).
        where.not(seller_id: nil, confirmed_at: nil)
      render json: serializer.index
    end

    def invite_existing_seller seller_id
      if @user.seller_ids.include? seller_id
        render json: { errors: [
          { email: "This user is already member of your team" }
        ] }, status: :unprocessable_entity
      elsif !@user.is_seller?
        render json: { errors: [
          { email: "This user has already registered with non-supplier account." }
        ] }, status: :unprocessable_entity
      elsif !@user.confirmed?
        render json: { errors: [
          { email: "This address is not confirmed yet." }
        ] }, status: :unprocessable_entity
      else
        SharedResources::RemoteNotification.create_notification(
          recipients: [@user.id],
          subject: "Your are invited by #{current_user.full_name || current_user.email} to join their supplier",
          body: "By accepting this invitation you will be able to update this company profile. If you are already member of another team, you will have access to both teams.",
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
        render json: serializer.show, status: :created
      end
    end

    def create
      raise SharedModules::MethodNotAllowed unless current_user.is_seller? && current_user.seller_id

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
