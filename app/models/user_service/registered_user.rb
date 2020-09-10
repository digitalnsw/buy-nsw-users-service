module UserService
  class RegisteredUser < ApplicationRecord
    self.table_name = 'registered_users'

    def self.import xml_doc
      rows = xml_doc.css('row').to_a.map do |row|
        fields = row.css("field").map do |field|
          [field['name'], field.inner_text]
        end.compact.to_h
      end

      rows.each do |row|
        next if row['RegisteredUserUUID'].blank? || row['Email'].blank?

        ru = RegisteredUser.find_or_initialize_by(uuid: row['RegisteredUserUUID'])
        ru.email = row['Email'].downcase
        ru.fields = row
        ru.save!

        next if row['Suspended'].to_i == 1

        u = ::User.find_by(uuid: row['RegisteredUserUUID'])

        next if u.present?

        u = ::User.find_or_initialize_by(email: row['Email'].downcase)

        u.uuid = ru.uuid
        u.full_name ||= (ru.fields['GivenName'].to_s + ' ' + ru.fields['Surname'].to_s).strip
        u.roles << 'seller' unless u.is_seller? || u.is_buyer?
        u.password = u.password_confirmation = SecureRandom.hex(32) unless u.persisted?

        abn = row['ABN']
        if abn.present? && ABN.valid?(abn)
          abn = ABN.new(abn).to_s
          seller_id = ::SellerVersion.where(abn: abn, state: ['approved','pending']).first&.seller_id
          seller_id ||= ::SellerVersion.where(abn: abn, next_version_id: nil).first&.seller_id

          if seller_id.present? && u.seller_id != seller_id
            u.seller_id ||= seller_id
            u.seller_ids |= [seller_id]
          end
        end

        u.skip_confirmation_notification!
        u.skip_sync = true
        u.save!
      end
    end
  end
end