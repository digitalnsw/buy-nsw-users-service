require_dependency "user_service/application_controller"

module UserService
  class UsersController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false, only: [:add_to_team, :request_declined, :destroy, :remove_from_supplier]
    before_action :authenticate_service, only: [:add_to_team, :request_declined, :seller_team, :seller_owners, :destroy, :remove_from_supplier, :get_by_id, :get_by_email]
    before_action :authenticate_user, only: [:index, :create, :update, :switch_supplier]
    before_action :authenticate_service_or_user, only: [:show]
    before_action :downcase_and_strip_email
    before_action :set_current_user, only: [:update, :index, :switch_supplier]
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

    def switch_supplier
      seller_id = params[:seller_id].to_i
      if @user&.is_seller? && @user.seller_ids.include?(seller_id)
        @user.update_attributes(seller_id: seller_id)
        #reset session user
        UserService::SyncTendersJob.perform_later @user.id
      else
        raise SharedModules::NotAuthorized.new
      end
    end

    def make_owner_if_first user, s_id
      has_owners = ::User.confirmed.where.not(id: user.id).where("#{s_id} = any(seller_ids)").exists?
      user.grant! s_id, :owner unless has_owners
    end

    # This method is called when admin assignes a user or when they iniate a supplier
    def add_to_team
      u = ::User.find(params[:id])
      s_id = params[:seller_id].to_i

      u.update_attributes!(seller_id: s_id, seller_ids: u.seller_ids | [s_id])

      UserService::SyncTendersJob.perform_later u.id

      make_owner_if_first u, s_id

      privileges = params[:privileges]&.to_a&.map(&:to_sym) || []
      privileges.each do |p|
        u.grant! s_id, p
      end

      abn = ABN.new(params[:abn]).to_s

      if abn.present?
        SharedResources::RemoteNotification.create_notification(
          unifier: 'accepted_' + u.id.to_s + '_' + Time.now.to_i.to_s,
          recipients: [u.id],
          subject: "Your join request was accepted",
          body: "Your request to join supplier with ABN #{abn} was accepted.",
          fa_icon: 'user-check',
          actions: [],
        )
      end

      render json: { message: 'User successfully added to supplier' }, status: :accepted
    end

    def request_declined
      u_id = params[:id].to_i
      abn = ABN.new(params[:abn]).to_s

      if abn.present?
        SharedResources::RemoteNotification.create_notification(
          unifier: 'declined_' + u_id.to_s + '_' + Time.now.to_i.to_s,
          recipients: [u_id],
          subject: "Your join request was declined",
          body: "Your request to join supplier with ABN #{abn} was declined.",
          fa_icon: 'user-times',
          actions: [],
        )
      end
    end

    def remove_from_supplier
      user = ::User.find_by(id: params[:id])
      s_id = params[:seller_id].to_i

      if user.present?
        user.seller_ids.delete s_id
        user.seller_id = user.seller_ids.first unless user.seller_id.in? user.seller_ids
        user.revoke s_id
        user.save
      end

      UserService::SyncTendersJob.perform_later user.id

      render json: { message: 'User successfully removed from supplier' }, status: :accepted
    end

    def destroy
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
      @user = ::User.where(id: params[:id]).first
      render json: serializer.show
    end

    def get_by_email
      @user = ::User.where(email: params[:email]).first
      render json: serializer.show
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

    def seller_team
      @users = ::User.where("? = any(seller_ids)", params[:seller_id].to_i).to_a
      render json: serializer.index
    end

    def seller_owners
      seller_id = params[:seller_id].to_i
      @users = ::User.where("? = any(seller_ids)", seller_id).to_a.select do |u|
        u.can? seller_id, :owner
      end
      render json: serializer.index
    end

    def update_full_name new_name
      old_name = @user.full_name
      @user.full_name = new_name
      if @user.has_changes_to_save?
        if @user.save
          log_user_event!("User updated full name from #{old_name} to #{@user.full_name}")
          return true
        else
          render json: { errors: [{ full_name: 'Name is invalid' }] }, status: :unprocessable_entity
          return false
        end
      end
      true
    end

    def update_opted_out opted_out
      @user.opted_out = opted_out.to_s == 'true'
      if @user.has_changes_to_save?
        if @user.save
          log_user_event!("User opted #{@user.opted_out ? 'out' : 'in'}")
          return true
        else
          render json: { errors: [{ opted_out: 'Opt in/out failed' }] }, status: :unprocessable_entity
          return false
        end
      end
      true
    end

    def update_email new_email
      new_email = new_email&.downcase&.strip

      if @user.email == new_email && @user.unconfirmed_email.present?
        old_email = @user.unconfirmed_email
        @user.unconfirmed_email = nil
        if @user.save
          log_user_event!("User updated email from #{old_email} back to #{new_email}")
          return true
        else
          render json: { errors: [{ email: 'Email address is currently in use or invalid' }] }, status: :unprocessable_entity
          return false
        end
      elsif @user.email != new_email
        old_email = @user.email
        @user.email = new_email
        if @user.save
          log_user_event!("User requested email update from #{old_email} to #{new_email}")
          return true
        else
          render json: { errors: [{ email: 'Email address is currently in use or invalid' }] }, status: :unprocessable_entity
          return false
        end
      end
      true
    end

    def update_password new_password
      if new_password.present?
        @user.reload
        if @user.reset_password(new_password, new_password)
          log_user_event!("User password updated")
          return true
        else
          render json: { errors: [{ newPassword: 'Password was not accepted' }] }, status: :unprocessable_entity
          return false
        end
      end
      true
    end

    def update
      unless @user&.valid_password?(params[:user][:currentPassword])
        render json: { errors: [{ currentPassword: 'Invalid Password' }] }, status: :unprocessable_entity
      else
        update_full_name(params[:user][:full_name]) or return
        update_opted_out(params[:user][:opted_out]) or return
        update_email(params[:user][:email]) or return
        update_password(params[:user][:newPassword]) or return

        UserService::SyncTendersJob.perform_later @user.id

        sign_in(@user, bypass: true)
        reset_session_user @user
        render json: serializer.show, status: :accepted
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
          if params[:type] == 'buyer' && !SharedResources::RemoteBuyer.check_email(params[:email])
            render json: { errors: [ {
              email: 'Please use a recognised Australian Government email address'
            } ] }, status: :unprocessable_entity
            return
          end
          user = ::User.new(
            email: params[:email],
            has_password: true,
            full_name: params[:full_name],
            password: params[:password],
            password_confirmation: params[:password],
            roles: [params[:type]]
          )
          if user.save
            UserService::SyncTendersJob.perform_later user.id
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

        if @user.confirmation_sent_at < 4.weeks.ago
          @user.update_columns(confirmation_token: SecureRandom.base58(20))
        end
        @user.update_columns(confirmation_sent_at: Time.now)

        if @user.invited?
          mailer = SellerInvitationMailer.with(user: @user)
          if @user.uuid.present? && @user.confirmed?
            mailer.tender_user_email.deliver_later
          elsif @user.uuid.present?
            mailer.tender_invitation_email.deliver_later
          else
            mailer.seller_invitation_email.deliver_later
          end
        else
          @user.send_confirmation_instructions
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
          UserService::SyncTendersJob.perform_later @user.id
          seller_id = SharedResources::RemoteWaitingSeller.initiate_seller @waiting_seller.id
          @user.update_attributes!(seller_id: seller_id, seller_ids: [seller_id])
          @user.grant!(seller_id, :owner)
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
        raise SharedModules::AlertError.new("This link is invalid or has expired. If you haven't already confirmed your account, please use the link in the most recent email you received.")
      elsif @user.confirmed?
        raise SharedModules::AlertError.new("Invitation already accepted")
      else
        logout_user current_user
        ::User.transaction do
          @user.confirm
          @user.reset_password(params[:password], params[:password])
          @user.update_attributes!(full_name: params[:full_name], has_password: true)
        end
        UserService::SyncTendersJob.perform_later @user.id
        log_invitation_event!
        login_user @user
        render json: { message: 'Invitation accepted' }, status: :accepted
      end
    end

    def confirm_email
      if @user.nil?
        redirect_to "/failure/confirmation_token_not_found"
        return
      end

      #FIXME: This case may never happen as user's token is removed during confirmation
      if @user && @user.confirmed? && !@user.unconfirmed_email?
        redirect_to "/failure/email_already_confirmed"
        return
      end

      unless @user.has_password
        redirect_to "/confirm-invitation/"+params[:token]
        return
      end

      unless @user.confirm
        redirect_to "/failure/email_confirmation_failed"
        return
      end

      @user.seller_ids.each do |s_id|
        make_owner_if_first @user, s_id
      end

      logout_user current_user
      login_user @user      
      SharedResources::RemoteBuyer.auto_register(email: @user.email,
                                                 name: @user.full_name.to_s,
                                                 user_id: @user.id) if @user.is_buyer?
      UserService::SyncTendersJob.perform_later @user.id
      log_user_event!("User confirmed email")
      redirect_to "/success/email_confirmation"
    end

    def unlock_account
      # params: unlock_token
      # success: redirect /success/account_unlocked
    end

    def approve_buyer
      begin
        SharedResources::RemoteBuyer.manager_approval(params[:manager_approval_token])
        redirect_to "/success/manager_approved"
      rescue ActiveResource::ResourceNotFound => e
        redirect_to "/failure/manager_approved"
      rescue => exception
        Airbrake.notify_sync exception
        redirect_to "/failure/manager_approved"
      end
    end

    def unsubscribe
      @user = ::User.find_by(email: params[:email])
      if @user && Digest::SHA2.hexdigest(@user.email + ENV['OPTOUT_SECRET']) == params[:token]
        log_user_event! "Unsubscribed"
        @user.update_attributes!(opted_out: true)
        redirect_to "/success/unsubscribe"
      else
        redirect_to "/failure/unsubscribe"
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

    def downcase_and_strip_email
      params[:email] = params[:email].downcase.strip if params[:email].present?
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
      @user = nil if @user && @user.confirmation_sent_at < 4.weeks.ago
    end

    def user_params
      params.require(:user).permit(:email)
    end
  end
end
