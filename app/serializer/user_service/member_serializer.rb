module UserService
  class MemberSerializer
    def initialize(member:, members:, seller_id:)
      @members = members
      @member = member
      @seller_id = seller_id
    end

    def attributes(member)
      return unless member
      {
        id: member.id,
        full_name: member.full_name,
        email: member.email,
        owner: member.can?(@seller_id, :owner),
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
