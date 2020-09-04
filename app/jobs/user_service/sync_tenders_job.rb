require 'net/http'

module UserService
  class SyncTendersJob < SharedModules::ApplicationJob
    include SharedModules::Encrypt

    def perform user_id
      user = ::User.find user_id.to_i
      return unless user.is_seller?
      name = user.full_name || ''
      firstname = name.partition(' ').first
      firstname = 'Firstname' if firstname.blank?
      lastname = name.partition(' ').last
      lastname = 'Lastname' if lastname.blank?
      host = URI(ENV['ETENDERING_URL']).host
      version = user.seller&.last_version
      sme_hash = {
        'sole' => '0-19',
        '2to4' => '0-19',
        '5to19' => '0-19',
        '20to49' => '20-100',
        '50to99' => '20-100',
        '100to199' => '101-200',
        '200plus' => '200+',
      }
      hash = {
        "iss": "SUPPLIER_HUB",
        "aud": host,
        "iat": Time.now.to_i,
        "exp": Time.now.to_i + 30,
        "nonce": rand(1<<60),
        "firstname": firstname,
        "surname": lastname,
        "email": user.email,
        "companyName": version&.name || "PTY LTD",
        "SMEStatus": sme_hash[version&.number_of_employees.to_s] || "0-19",
        "ABN": version&.abn || "51824753556",
        "age": "1",
        "addressLine1": version&.addresses&.first&.adress || "1",
        "addressLine2": version&.addresses&.first&.address_2 || "",
        "city": version&.addresses&.first&.suburb || "Sydney",
        "state": version&.addresses&.first&.state || "NSW",
        "postcode": version&.addresses&.first&.postcode || "2000",
        "country": version&.addresses&.first&.country || "Australia",
        "companyPhone": version&.addresses&.first&.contact_phone || "0"
      }
      hash['sub'] = user.uuid if user.uuid
      token = encrypt_and_sign(hash)
      uri = if user.uuid
        URI(ENV['ETENDERING_URL'] + '?event=public.supplierhubuser.update&supplierHubDetails='+token)
      else
        URI(ENV['ETENDERING_URL'] + '?event=public.supplierhubuser.create&supplierHubDetails='+token)
      end
      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new uri
        request['authority'] = host
        request['pragma'] = 'no-cache'
        request['cache-control'] = 'no-cache'
        request['User-Agent'] = 'Supplier hub'
        response = http.request request
      end
      result = JSON.parse(response.body)
      user.update_attributes!(uuid: result['registeredUserUUID']) unless user.uuid
      raise result['errors'] if result['errors'].present?
    end
  end
end
