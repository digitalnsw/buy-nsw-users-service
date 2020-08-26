module UserService
  class SsoController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    before_action :check_impersonating
    before_action :sanitize_urls

    def sanitize_urls
      if params[:redirectString].present?
        raise SharedModules::NotAcceptable.new unless params[:redirectString] =~ URI::regexp
        raise SharedModules::NotAcceptable.new unless params[:redirectString].starts_with?('https:')
      end
      
      if params[:loginURL].present?
        raise SharedModules::NotAcceptable.new unless params[:loginURL] =~ URI::regexp
        raise SharedModules::NotAcceptable.new unless params[:loginURL].starts_with?('https:')
      end
    end

    def check_impersonating
      raise MethodNotAllowed.new('SSO does not work in impersonating mode') if current_user != true_user
    end

    def generate_token
      data = {
        email: current_user.email,
        sub: current_user.uuid,
        iss: 'SUPPLIER_HUB',
        iat: Time.now.to_i,
        exp: Time.now.to_i + 30,
        redirectString: params[:redirectString],
        nonce: rand(1<<60),
        aud: URI.parse(params[:loginURL]).host,
      }
      private_key = OpenSSL::PKey::RSA.new File.read(Rails.root.join('sso_rsa.pem').to_s), ENV['SSO_KEY_PASS']
      # TODO: Log this token, when tenders implemented the nonce invalidator
      JWT.encode(data, private_key, 'RS512')
    end

    def logout
      if current_user
        sign_out current_user
        reset_session
        reset_c_session
      end
      redirect_to params[:redirectString]
    end

    def login
      if current_user
        sync
      else 
        redirect_to '/ict/login?redirectString=' +
          URI.escape(params[:redirectString].to_s) + '&loginURL=' +
          URI.escape(params[:loginURL].to_s)
      end
    end

    def sync
      url = params[:loginURL]
      redirect_to url + (url.include?('?') ? '&' : '?') + 'AuthorisedSupplierHubToken=' + generate_token
    end

    def signup
    end

    def profile
    end
  end
end
