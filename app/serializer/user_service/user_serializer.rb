module UserService
  class UserSerializer
    def initialize(user:, users:)
      @users = users
      @user = user
    end

    def attributes(user)
      return nil unless user
      {
        id: user.id,
        email: user.unconfirmed_email || user.email,
        full_name: user.full_name,
        confirmed_email: user.email,
        newPassword: '',
        currentPassword: '',
        roles: user.roles.to_a,
        seller_id: user.seller_id,
        confirmed: user.unconfirmed_email.nil? || user.email == user.unconfirmed_email,
        opted_out: user.opted_out,
        active: user.confirmed? && !user.suspended,
      }
    end

    def show
      { user: attributes(@user) }
    end

    def index
      {
        users: @users.map do |user|
          attributes(user)
        end
      }
    end
  end
end
