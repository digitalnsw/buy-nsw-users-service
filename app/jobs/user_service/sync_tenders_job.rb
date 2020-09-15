require 'net/http'

module UserService
  class SyncTendersJob < SharedModules::ApplicationJob
    include SharedModules::Encrypt

    def present_or first, second
      first&.strip.present? ? first&.strip : second
    end

    def perform user_id
      user = ::User.find user_id.to_i
      name = user.full_name || ''
      firstname = present_or(name.partition(' ').first, 'Firstname')
      lastname = present_or(name.partition(' ').last, 'Lastname')

      host = URI(ENV['ETENDERING_URL']).host
      version = user.seller&.live? ? user.seller.latest_version : nil

      # out side au is not in the list by purpose
      state_hash = {
        'nsw' => 'NSW',
        'vic' => 'VIC',
        'qld' => 'QLD',
        'sa'  => 'SA',
        'act' => 'ACT',
        'wa'  => 'WA',
        'nt'  => 'NT',
        'tas' => 'TAS',
      }
      state = state_hash[version&.addresses&.first&.state] || "NSW"
      country = ISO3166::Country.new(version&.addresses&.first&.country)&.name&.upcase || 'AUSTRALIA'
      abn = ABN.valid?(version&.abn) ? version&.abn.gsub(' ', '') : ''

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
        "companyName": present_or(version&.name, "Business name"),
        "SMEStatus": sme_hash[version&.number_of_employees.to_s] || "0-19",
        "ABN": abn,
        "addressLine1": present_or(version&.addresses&.first&.adress, "Address"),
        "addressLine2": version&.addresses&.first&.address_2 || "",
        "city": present_or(version&.addresses&.first&.suburb, "City"),
        "postcode": present_or(version&.addresses&.first&.postcode, "Postcode"),
        "state": country == 'AUSTRALIA' ? state : 'Outside Australia',
        "country": country,
        "companyPhone": present_or(version&.contact_phone, "000"),
      }

      if user.uuid
        hash['sub'] = user.uuid
      else
        password = SecureRandom.base58(39) + rand(10).to_s
        password.gsub!(/#{firstname}/i, '')
        password.gsub!(/#{lastname}/i, '')
        password.gsub!(/#{user.email}/i, '')
        hash['password'] = password
      end
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
