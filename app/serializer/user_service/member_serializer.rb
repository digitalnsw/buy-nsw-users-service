module UserService
  class MemberSerializer
    def initialize(member:, members:)
      @members = members
      @member = member
    end

    def attributes(member)
      {
        id: member.id,
        email: member.email,
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
