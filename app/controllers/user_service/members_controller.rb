require_dependency "user_service/application_controller"

module UserService
  class MembersController < UserService::ApplicationController
    before_action :authenticate_user

    def serializer
      UserService::MemberSerializer.new(member: @member, members: @members)
    end

    def index
      @members = ::User.where(seller_id: current_user.seller_id).where.not(seller_id: nil)
      render json: serializer.index
    end

    def create
      raise SharedModules::MethodNotAllowed unless current_user.is_seller? && current_user.seller_id
      @member = ::User.new(member_params)
      @member.seller_id = current_user.seller_id
      @member.roles = ['seller']
      @member.password = @member.password_confirmation = SecureRandom.hex(32)
      @member.skip_confirmation_notification!

      if @member.save
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
