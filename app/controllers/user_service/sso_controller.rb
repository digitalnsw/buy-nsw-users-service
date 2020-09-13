module UserService
  class SsoController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    before_action :check_impersonating
    before_action :sanitize_urls

    def raise_error
      raise SharedModules::NotAcceptable.new
    end

    def redirectString
      # FIXME : This check is to detect loops
      if params[:redirectString].to_s.length > 2048
        raise "An error raised signing you in, please contact us at buy.nsw@customerservice.nsw.gov.au!"
      end
      params[:redirectString]
    end

    def loginURL
      params[:loginURL]
    end

    def tenders_host
      URI.parse(ENV['ETENDERING_URL']).host
    end

    def sanitize_urls
      if redirectString.present?
        raise_error unless redirectString =~ URI::regexp
        uri = URI.parse(redirectString)
        raise_error unless uri.scheme == 'https'
        raise_error unless uri.host.ends_with?('.nsw.gov.au')
      end
      
      if loginURL.present?
        raise_error unless loginURL =~ URI::regexp
        uri = URI.parse(loginURL)
        raise_error unless uri.scheme == 'https'
        raise_error unless uri.host.ends_with?('.nsw.gov.au')
      end
    end

    def check_impersonating
      raise SharedModules::MethodNotAllowed.new('SSO does not work in impersonating mode') if current_user != true_user
    end

    def generate_token
      data = {
        id: current_user&.id,
        email: current_user&.email,
        sub: current_user&.uuid,
        iss: 'SUPPLIER_HUB',
        iat: Time.now.to_i,
        exp: Time.now.to_i + 30,
        nonce: rand(1<<60),
        aud: URI.parse(loginURL).host,
      }
      # TODO: Log this token, when tenders implemented the nonce invalidator
      encrypt_and_sign data
    end

    def logout
      raise_error unless redirectString.present?
      if current_user
        sign_out current_user
        reset_session
        reset_c_session
      end
      redirect_to redirectString
    end

    def login
      raise_error unless loginURL.present?
      raise_error unless redirectString.present?
      if current_user
        sync
      else 
        redirect_to '/ict/login?redirectString=' +
          CGI.escape(redirectString) + '&loginURL=' +
          CGI.escape(loginURL)
      end
    end

    def soft_redirect url
      render inline: "<html><script>window.location='#{url.gsub("'", "\\'")}';</script></html>"
    end

    def sync
      if current_user.present?
        raise_error unless loginURL.present?
        soft_redirect loginURL + generate_token + '&redirectString=' + CGI.escape(redirectString)
      else
        raise_error unless redirectString.present?
        redirect_to redirectString
      end
    end

    def signup
      raise_error unless loginURL.present?
      if current_user
        sync
      else
        redirect_to '/ict/signup/supplier'
      end
    end

    def profile
      redirect_to '/ict/account/settings'
    end

    def forgot_password
      redirect_to '/ict/forgot-password'
    end
  end
end
