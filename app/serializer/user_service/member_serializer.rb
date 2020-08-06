module UserService
  class MemberSerializer
    def initialize(member:, members:)
      @members = members
      @member = member
    end

    def attributes(member)
      {
        id: member.id,
        full_name: member.full_name,
        email: member.email,
        confirmed: member.confirmed?
      }
    end

    def show
      { member: attributes(@member) }
    end

    def index
      {
        members: @members.map do |member|
          attributes(member)
        end
      }
    end
  end
end
