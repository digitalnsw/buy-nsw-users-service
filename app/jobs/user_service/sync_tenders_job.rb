require 'net/http'

module UserService
  class SyncTendersJob < SharedModules::ApplicationJob
    include SharedModules::Encrypt

    def perform user_id
      user = ::User.find user_id.to_i
      name = user.full_name || ''
      token = encrypt_and_sign({
        "iss": "SUPPLIER_HUB",
        "aud": URI.parse(ENV['ETENDERING_URL']).host,
        "iat": Time.now.to_i,
        "exp": Time.now.to_i + 30,
        "nonce": rand(1<<60),
        "firstname": name.partition(' ').first || 'Firstname',
        "surname": name.partition(' ').last || 'Lastname',
        "email": user.email,
        "companyName": "PTY LTD",
        "SMEStatus": "0-20",
        "ABN": "51824753556",
        "age":"1",
        "address":{
          "addressLine1":"1 First St",
          "addressLine2":"",
          "city":"Sydney",
          "state":"NSW",
          "postcode":"2000",
          "country":"Australia"
        },
        "companyPhone":"0"
      })
      uri = URI(ENV['ETENDERING_URL'] + '?event=public.supplierhubuser.create&supplierHubDetails='+token)
      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new uri
        response = http.request request
      end
      user.update_attributes!(uuid: JSON.parse(response.body)['registeredUserUUID'])
    end
  end
end
