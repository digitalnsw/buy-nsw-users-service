module UserService
  class RegisteredUser < ApplicationRecord
    self.table_name = 'registered_users'

    def self.convert_state fields
      if fields['Country'].present? && fields['Country'].upcase != 'AUSTRALIA'
        'outside_au'
      elsif fields['State']&.downcase&.in? ["nsw", "act", "nt", "qld", "sa", "tas", "vic", "wa"]
        fields['State'].downcase
      else
        ''
      end
    end

    def self.import xml_doc
      abn_ex_h = {
        "NE" => "non-exempt",
        "EN" => "non-australian",
        "EI" => "insufficient-turnover",
        "EO" => "other",
      }
      num_emp_h = {
        "0-19" => '5to19',
        "20-100" => '50to99',
        "101-200" => '100to199',
        "200+" => '200plus',
      }

      rows = xml_doc.css('row').to_a.map do |row|
        fields = row.css("field").map do |field|
          [field['name'], field.inner_text]
        end.compact.to_h
      end

      rows.each do |row|
        begin
          next if row['RegisteredUserUUID'].blank? || row['Email'].blank?

          ru = RegisteredUser.find_or_initialize_by(uuid: row['RegisteredUserUUID'])
          ru.email = row['Email'].downcase
          ru.fields = row
          ru.save!

          next if row['Suspended'].to_i == 1

          u = ::User.find_by(uuid: row['RegisteredUserUUID'])

          u ||= ::User.find_or_initialize_by(email: row['Email'].downcase)

          u.uuid = ru.uuid
          #FIXME: below line doesn't work! it doesn't update the email column
          u.email = ru.email
          u.full_name = (ru.fields['GivenName'].to_s + ' ' + ru.fields['Surname'].to_s).
            gsub(/[^a-zA-Z0-9 .'\-]/, ' ').gsub(/ +/, ' ').strip if u.full_name.blank?
          u.roles << 'seller' unless u.is_seller? || u.is_buyer?
          u.password = u.password_confirmation = SecureRandom.hex(32) unless u.has_password?

          abn = row['ABN']&.gsub('-', '')
          if abn.present? && ABN.valid?(abn)
            abn = ABN.new(abn).to_s
            seller_id = ::SellerVersion.where(abn: abn, state: ['approved','pending']).first&.seller_id
            seller_id ||= ::SellerVersion.where(abn: abn).where.not(state: 'archived').first&.seller_id

            if seller_id.present? && u.seller_id != seller_id
              u.seller_id ||= seller_id
              u.seller_ids |= [seller_id]
            end
          end

          if u.seller_id.nil?
            abn = ABN.new(abn).to_s
            seller = SellerService::Seller.create!(state: :draft, ru_uuid: ru.uuid)
            sv = SellerService::SellerVersion.create!({
              seller_id: seller.id,
              state: :draft,
              started_at: Time.now,
              schemes_and_panels: [],
              name: row['CompanyName'] || '',
              abn: abn,
              abn_exempt: abn_ex_h[row['ABNExempt']],
              abn_exempt_reason: row['ABNExemptReason'] || '',
              indigenous: row['IsATSIOwned'].to_i == 1,
              addresses: [
                {
                  address: row["Address1"] || '',
                  address_2: row["Address2"] || '',
                  address_3: row["OfficeName"] || '',
                  suburb: row["City"] || '',
                  postcode: row["Postcode"] || '',
                  state: convert_state(row),
                  country: ISO3166::Country.find_country_by_name(
                           row["Country"])&.un_locode || '',
                }
              ],

              contact_first_name: row["GivenName"] || '',
              contact_last_name: row["Surname"] || '',
              contact_phone: row["CompanyPhone"] || '',
              contact_email: row["Email"].downcase || '',
              contact_position: '',

              number_of_employees: num_emp_h[row["SMEStatus"]] || '',
              australia_employees: num_emp_h[row["SMEStatus"]] || '',
              nsw_employees: num_emp_h[row["SMEStatus"]] || '',
            })
            u.seller_id ||= seller.id
            u.seller_ids |= [seller.id]
            u.grant seller.id, :owner
          end

          u.skip_confirmation_notification!
          u.save!
        rescue => e
          Airbrake.notify_sync(e.message, {
            RUUUID: row['RegisteredUserUUID'],
            trace: e.backtrace.select{|l|l.match?(/buy-nsw/)},
          })
        end
      end
    end
  end
end
