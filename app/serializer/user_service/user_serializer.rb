module UserService
  class UserSerializer
    def initialize(user:, users:)
      @users = users
      @user = user
    end

    def attributes(user)
      {
        id: user.id,
        email: user.unconfirmed_email || user.email,
        full_name: user.full_name,
        confirmed_email: user.email,
        roles: user.roles.to_a,
        seller_id: user.seller_id,
        confirmed: user.unconfirmed_email.nil? || user.email == user.unconfirmed_email
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
