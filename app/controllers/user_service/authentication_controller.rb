module UserService
  class AuthenticationController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def logout
      @sign_out = true
      stop_impersonating_user if current_user != true_user
      if current_user
        sign_out current_user
        reset_session
      end
      user_info
    end

    def login
      user = ::User.find_by_email(params[:email]&.downcase)
      if user && user.last_failed_at && user.failed_count && (Time.now - user.last_failed_at).to_i < 3600 && user.failed_count >= 10
        render json: { errors: [
          { password: "Your account has been locked. Try again in one hour"}
        ] }, status: :unprocessable_entity
      elsif user && !user.confirmed?
        render json: { errors: [
          { password: "Please confirm your email address first"}
        ] }, status: :unprocessable_entity
      elsif user&.valid_password?(params[:password])
        user.update_attributes!(last_failed_at: nil, failed_count: nil)

        reset_session
        user.remember_me = true if params[:remember].to_s == 'true'
        sign_in(user, scope: :user)

        user_info
      else
        if user.nil? && ::User.find_by_unconfirmed_email(params[:email]&.downcase)
          render json: { errors: [
            { password: "Please confirm your new email address or use your old one to login"}
          ] }, status: :unprocessable_entity
        else
          if user
            if user.last_failed_at && user.failed_count && (Time.now - user.last_failed_at).to_i < 3600
              user.update_attributes!(failed_count: user.failed_count + 1)
            else
              user.update_attributes!(last_failed_at: Time.now, failed_count: 1)
            end
          end
          render json: { errors: [
            { password: "Invalid Email or Password"}
          ] }, status: :unprocessable_entity
        end
      end
    end

    def user_info
      result = {
        config: {
          airbrake_js_project_id: ENV['AIRBRAKE_JS_PROJECT_ID'],
          airbrake_js_api_key: ENV['AIRBRAKE_JS_API_KEY'],
          google_analytics_tracking_id: ENV['GOOGLE_ANALYTICS_TRACKING_ID'],
          environment: if Rails.env.production?
            ENV['DEPLOYMENT_ENVIRONMENT'] || Rails.env
          else
            Rails.env
          end,
          build_version: defined?(APP_VERSION) && APP_VERSION,
          build_time: defined?(APP_VERSION_TIME) && APP_VERSION_TIME,
          etendering_url: ENV['ETENDERING_URL']
        },
        csrf_token: session[:_csrf_token] || form_authenticity_token,
      }
      if current_user.present? && !@sign_out
        me = update_session_user current_user
        result.merge!({
          user: {
            id: me.id,
            email: me.email,
            full_name: me.full_name,
            roles: me.roles.map(&:to_s),
            seller_id: me.seller_id,
            seller_live: me.seller_is_live?,
            buyer_id: me.buyer_id,
            can_buy: me.can_buy?
          },
        })
        if current_user != true_user
          result.merge!({
            true_user: {
              id: true_user.id,
              email: true_user.email,
            }
          })
        end
      end
      render json: result
    end
  end
end
