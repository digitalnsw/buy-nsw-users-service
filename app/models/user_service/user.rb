module UserService
  class User < UserService::ApplicationRecord
    self.table_name = 'users'
    extend Enumerize

    acts_as_paranoid column: :discarded_at

    devise :database_authenticatable, :registerable,
           :confirmable, :recoverable, :rememberable,
           :trackable, :validatable, :async,
           :timeoutable

    enumerize :roles, in: ['seller', 'buyer', 'admin', 'superadmin'], multiple: true

    def first_name
      full_name&.partition(' ')&.first&.strip
    end

    def last_name
      full_name&.partition(' ')&.last&.strip
    end
  end
end
