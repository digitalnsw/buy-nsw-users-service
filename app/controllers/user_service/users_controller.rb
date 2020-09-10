require_dependency "user_service/application_controller"

module UserService
  class UsersController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false, only: [:update_seller, :seller_owners, :destroy, :remove_from_supplier] 
    before_action :authenticate_service, only: [:update_seller, :seller_owners, :destroy, :remove_from_supplier, :get_by_id, :get_by_email]
    before_action :authenticate_user, only: [:index, :create, :update, :update_account]
    before_action :authenticate_service_or_user, only: [:show]
    before_action :downcase_email
    before_action :set_current_user, only: [:update, :update_account, :index]
    before_action :set_user_by_email, only: [:forgot_password, :resend_confirmation, :signup]
    before_action :set_user_by_token, only: [:accept_invitation, :confirm_email]

    def serializer
      UserService::UserSerializer.new(user: @user, users: @users)
    end

    def index
      if params[:current]
        render json: serializer.show
      end
    end

    def update_seller
      ::User.find(params[:id]).update_attributes!(seller_id: params[:seller_id].to_i)
    end

    def remove_from_supplier
      raise "Only superadmin may remove users" unless service_user.is_superadmin?

      user = ::User.find_by(id: params[:id])
      raise "User has multiple companies" if (user.seller_ids || []).size > 1

      if user.present?
        user.update_columns(seller_id: nil, seller_ids: [])
      end
      render json: { message: 'User successfully removed from supplier' }, status: :accepted
    end

    def destroy
      raise "Only superadmin may destroy users" unless service_user.is_superadmin?
      user = ::User.find_by(id: params[:id])
      if user.present?
        ::User.transaction do
          user.update_column(:email, user.email + '_' + Time.now.to_i.to_s)
          user.destroy
        end
      end
      render json: { message: 'User successfully destroyed' }, status: :accepted
    end

    def show
      if service_auth?
        set_user_by_id
      else
        set_current_user
      end
      render json: serializer.show
    end

    def get_by_id
      @users = ::User.where(id: params[:id])
      render json: serializer.index
    end

    def get_by_email
      @users = ::User.where(email: params[:email])
      render json: serializer.index
    end

    def create
      if @user.save
        render json: serializer.show, status: :created, location: @user
      else
        render json: { errors: [
          @user.errors&.messages&.map{|k,v|
            [k, k.to_s + ' ' + v.first.to_s]
          }.to_h
        ] }, status: :unprocessable_entity
      end
    end

    def log_user_event!(note)
      SharedResources::RemoteEvent.generate_token @user
      SharedResources::RemoteEvent.create_event(@user.id, 'User', current_user&.id || @user.id, 'Event::User', note)
    end

    def seller_owners
      @users = ::User.where(seller_id: params[:seller_id])
      render json: serializer.index
    end

    def update
      unless @user&.valid_password?(params[:user][:currentPassword])
        render json: { errors: [{ currentPassword: 'Invalid Password' }] }, status: :unprocessable_entity
      else
        if @user.full_name != params[:user][:full_name]
          @user.update_attributes!(full_name: params[:user][:full_name])
        end

        if (@user.unconfirmed_email || @user.email) != params[:user][:email]

          @user.email = params[:user][:email]
          unless @user.save
            render json: { errors: [{ email: 'Email address is currently in use or invalid' }] }, status: :unprocessable_entity
            return
          end
        end

        if params[:user][:newPassword].present?
          @user.reload
          unless @user.reset_password(params[:user][:newPassword], params[:user][:newPassword])
            render json: { errors: [{ newPassword: 'Password was not accepted' }] }, status: :unprocessable_entity
            return
          end
        end

        UserService::SyncTendersJob.perform_later @user.id

        sign_in(@user, bypass: true)
        reset_session_user @user
        log_user_event!("User email/password updated")
        render json: serializer.show, status: :accepted
      end
    end

    def update_account
      unless @user&.valid_password?(params[:currentPassword])
        render json: { errors: [{ password: 'Invalid Password' }] }, status: :unprocessable_entity
      else
        @user.update_attributes!(full_name: params[:full_name]) if @user.full_name != params[:full_name]

        if @user.email != params[:email]
          @user.email = params[:email]
          unless @user.save
            render json: { errors: [{ email: 'This email address is currently in use or invalid' }] }, status: :unprocessable_entity
            return
          end
        end

        if params[:newPassword].present?
          @user.reload
          unless @user.reset_password(params[:newPassword], params[:newPassword])
            render json: { errors: [{ newPassword: 'New password was not accepted' }] }, status: :unprocessable_entity
            return
          end
        end

        UserService::SyncTendersJob.perform_later @user.id

        sign_in(@user, bypass: true)
        reset_session_user @user

        log_user_event!("User email/password updated")
        render json: { message: 'User updated' }, status: :accepted
      end
    end

    def signup
      logout_user current_user
      if @user.present?
        render json: { errors: [{ email: 'This email address is not available'}] }, status: :unprocessable_entity
      else
        if ['seller', 'buyer'].exclude? params[:type]
          raise SharedModules::AlertError.new("Invalid user type")
        else
          user = ::User.new(
            email: params[:email],
            has_password: true,
            full_name: params[:full_name],
            password: params[:password],
            password_confirmation: params[:password],
            roles: [params[:type]]
          )
          if user.save
            render json: { message: 'User is created' }, status: :accepted
          else
            render json: { errors: [
              user.errors&.messages&.map{|k,v|
                [k, k.to_s + ' ' + v.first.to_s]
              }.to_h
            ] }, status: :unprocessable_entity
          end
        end
      end
    end

    def forgot_password
      if @user.nil?
        render json: { errors: [{email: "User does not exist"}] }, status: :unprocessable_entity
      elsif !@user.confirmed?
        render json: { errors: [{email: "User is not confirmed yet"}] }, status: :unprocessable_entity
      else
        logout_user current_user
        token = @user.send_reset_password_instructions
        @user.update_attributes(reset_password_token: token)
        log_user_event!("User asked for password reset")
        render json: { message: 'Reset email is sent' }, status: :accepted
      end
    end

    def resend_confirmation
      if @user.nil?
        render json: { errors: [{email: "User does not exist"}] }, status: :unprocessable_entity
      elsif @user.confirmed? && !@user.unconfirmed_email?
        render json: { errors: [{email: "Email is already confirmed"}] }, status: :unprocessable_entity
      else
        logout_user current_user

        if @user.confirmation_sent_at < 2.weeks.ago
          @user.update_columns(confirmation_token: SecureRandom.base58(20), confirmation_sent_at: Time.now)
        end

        if @user.invited?
          mailer = SellerInvitationMailer.with(user: @user)
          mailer.seller_invitation_email.deliver_later
        else
          @user.send_confirmation_instructions
          @user.update_column(:confirmation_sent_at, Time.now)
        end

        log_user_event!("User asked to resed confirmation")
        render json: { message: 'Instructions email is sent' }, status: :accepted
      end
    end

    def update_lost_password
      # NEVER CONFIRM USER IN UPDATE PASSWORD
      # BECAUSE USER CAN FIRST REQUEST CHANGE OF PASSWORD
      # THEN UPDATE THE EMAIL AND USE PASSWORD RESET LINK TO CONFIRM EMAIL
      # THIS WAY THEY CAN CONFIRM AN EMAIL WITHOUT ACCESS TO THAT MAILBOX

      @user = ::User.find_by(reset_password_token: params[:token])
      if @user.nil?
        raise SharedModules::AlertError.new("Token is invalid, you might have already use this link to reset password!")
      else
        logout_user current_user
        @user.reset_password(params[:password], params[:password])
        @user.update_column(:has_password, true)
        login_user @user
        log_user_event!("User updated lost password")
        render json: { message: 'Password updated' }, status: :accepted
      end
    end

    def log_invitation_event!
      SharedResources::RemoteEvent.generate_token @user
      SharedResources::RemoteEvent.create_event(@user.seller_id, 'Seller', @user.id, 'Event::Seller', "Joined by invitation")
    end

    def confirm_admin_invitation
      @waiting_seller = SharedResources::RemoteWaitingSeller.find_by_token params[:token]
      if @waiting_seller.nil?
        raise SharedModules::AlertError.new("Token is invalid! You probably have already used this link and registered!")
      elsif ::User.exists?(email: @waiting_seller.email)
        raise SharedModules::AlertError.new(@waiting_seller.email + " is already a registered user!")
      else
        @user = ::User.new(
          full_name: @waiting_seller.contact_name,
          email: @waiting_seller.email,
          has_password: true,
          password: params[:password],
          password_confirmation: params[:password],
          roles: ['seller'],
          confirmed_at: Time.now,
        )
        if @user.save
          seller_id = SharedResources::RemoteWaitingSeller.initiate_seller @waiting_seller.id, @user.id
          @user.update_attributes!(seller_id: seller_id, seller_ids: [seller_id])
          log_invitation_event!
          login_user @user
          render json: { message: 'Application started' }, status: :accepted
        else
           render json: { errors: [
             @user.errors&.messages&.map{|k,v|
               [k, k.to_s + ' ' + v.first.to_s]
             }.to_h
           ] }, status: :unprocessable_entity
        end
      end
    end

    def accept_invitation
      if @user.nil?
        raise SharedModules::AlertError.new("Token is invalid")
      elsif @user.confirmed?
        raise SharedModules::AlertError.new("Invitation already accepted")
      else
        logout_user current_user
        ::User.transaction do
          @user.confirm
          @user.reset_password(params[:password], params[:password])
          @user.update_attributes!(full_name: params[:full_name], has_password: true)
        end
        log_invitation_event!
        login_user @user
        render json: { message: 'Invitation accepted' }, status: :accepted
      end
    end

    def confirm_email
      if @user.nil?
        redirect_to "/ict/failure/confirmation_token_not_found"
        return
      end

      #FIXME: This case may never happen as user's token is removed during confirmation
      if @user && @user.confirmed? && !@user.unconfirmed_email?
        redirect_to "/ict/failure/email_already_confirmed"
        return
      end

      unless @user.confirm
        redirect_to "/ict/failure/email_confirmation_failed"
        return
      end

      logout_user current_user
      login_user @user      
      UserService::SyncTendersJob.perform_later @user.id
      log_user_event!("User confirmed email")
      redirect_to "/ict/success/email_confirmation"
    end

    def unlock_account
      # params: unlock_token
      # success: redirect /ict/success/account_unlocked
    end

    def approve_buyer
      begin
        SharedResources::RemoteBuyer.manager_approval(params[:manager_approval_token])
        redirect_to "/ict/success/manager_approved"
      rescue ActiveResource::ResourceNotFound => e
        redirect_to "/ict/failure/manager_approved"
      rescue => exception
        Airbrake.notify_sync exception
        redirect_to "/ict/failure/manager_approved"
      end
    end

    private

    def logout_user user
      reset_c_session
      if user.present?
        sign_out user
        reset_session
      end
    end

    def login_user user
      reset_session
      sign_in(user, scope: :user)
      reset_session_user user
      form_authenticity_token
    end

    def downcase_email
      params[:email] = params[:email].downcase if params[:email].present?
    end

    def set_current_user
      @user = ::User.find(current_user.id)
    end

    def set_user_by_id
      @user = ::User.find(params[:id])
    end

    def set_user_by_email
      @user = ::User.find_by(email: params[:email]) || ::User.find_by(unconfirmed_email: params[:email])
    end

    def set_user_by_token
      @user = ::User.find_by(confirmation_token: params[:token])
    end

    def user_params
      params.require(:user).permit(:email)
    end
  end
end
