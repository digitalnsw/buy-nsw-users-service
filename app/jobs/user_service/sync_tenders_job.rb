require 'net/http'

module UserService
  class SyncTendersJob < SharedModules::ApplicationJob
    include SharedModules::Serializer
    include SharedModules::Encrypt

    def post_token user, host, hash
      token = encrypt_and_sign(hash)

      url = if user.uuid
        ENV['ETENDERING_URL'] + '?event=public.supplierhubuser.update'
      else
        ENV['ETENDERING_URL'] + '?event=public.supplierhubuser.create'
      end

      uri = URI(url)

      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data({'supplierHubDetails' => token})
      request['authority'] = host
      request['pragma'] = 'no-cache'
      request['cache-control'] = 'no-cache'
      request['Authorization'] = 'Basic ' + ENV['ETENDERING_WAF_SECRET']
      response = https.request request

      begin
        log = AnalyticsService::UserSync.create(
          token: token,
          url: url,
          date_hour: Time.now.utc.strftime('H_%Y-%m-%d_%H'),
          sent_at: Time.now.utc,
          user_id: user&.id,
          action: 'user_sync',
          status: response.code,
          response: sanitize(response.body),
        )
        log.save
      rescue => e
        Airbrake.notify_sync(e.message, {
          user_id: user&.id,
          trace: e.backtrace.select{|l|l.match?(/buy-nsw/)},
        })
      end

      JSON.parse(response.body)
    end

    def present_or first, second
      first&.strip.present? ? first&.strip : second
    end

    def perform user_id
      return unless ENV['ETENDERING_URL'].present?
      user = ::User.find user_id.to_i
      name = user.full_name || ''
      firstname = present_or(name.partition(' ').first, 'Firstname')
      lastname = present_or(name.partition(' ').last, 'Lastname')

      host = URI(ENV['ETENDERING_URL']).host
      version = user.seller&.live? ? user.seller.last_version : nil

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

      abr = SharedModules::Abr.lookup(version&.abn)
      abn = if abr && abr[:status] == 'Active'
              version&.abn.gsub(' ', '')
            else
              ''
            end

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
        "addressLine1": present_or(version&.addresses&.first&.address, "Address"),
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

      result = post_token user, host, hash
      new_uuid = result['registeredUserUUID']
      user.update_attributes!(uuid: new_uuid) if new_uuid.present? && user.uuid != new_uuid
      raise result['errors'] if result['errors'].present?
    end
  end
end
