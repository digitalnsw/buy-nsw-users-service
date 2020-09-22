module UserService
  class SsoController < UserService::ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    before_action :check_impersonating
    before_action :sanitize_urls

    def raise_error
      raise SharedModules::NotAcceptable.new
    end

    def redirectString
      params[:redirectString]
    end

    def nonce
      nonce = params[:nonce].to_s
      raise_error if nonce.present? && !nonce.match?(/\A[a-zA-Z0-9]{10,}\Z/)
      nonce
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
        # FIXME : This check is to detect loops
        if redirectString.length > 2048
          Airbrake.notify_sync("redirectString too long!", {
            redirectString: redirectString,
            current_user: current_user&.id,
          })
          raise_error
        end
      end
      
      if loginURL.present?
        raise_error unless loginURL =~ URI::regexp
        uri = URI.parse(loginURL)
        raise_error unless uri.scheme == 'https'
        raise_error unless uri.host.ends_with?('.nsw.gov.au')
        # FIXME : This check is to detect loops
        if loginURL.length > 2048
          Airbrake.notify_sync("loginURL too long!", {
            loginURL: loginURL,
            current_user: current_user&.id,
          })
          raise_error
        end
      end
    end

    def check_impersonating
      raise SharedModules::MethodNotAllowed.new('SSO does not work in impersonating mode') if current_user != true_user
    end

    def generate_token
      data = {
        id: current_user&.id,
        email: current_user&.email,
        name: current_user&.full_name,
        role: current_user&.is_seller ? 'seller' : 'buyer',
        seller_ids: current_user&.seller_ids,
        sub: current_user&.uuid,
        iss: 'SUPPLIER_HUB',
        iat: Time.now.to_i,
        exp: Time.now.to_i + 30,
        nonce: (nonce.present? ? nonce : SecureRandom.base58(10)),
        aud: URI.parse(loginURL).host,
      }.select{|k,v|v}
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
        redirect_to '/ict/login?nonce=' +
          nonce + '&redirectString=' +
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
