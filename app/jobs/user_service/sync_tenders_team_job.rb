module UserService
  class SyncTendersTeamJob < SharedModules::ApplicationJob
    include SharedModules::Encrypt

    def perform seller_id
      team = User.where(seller_id: seller_id).to_a
      team.each do |u|
        SyncTendersJob.perform_later u.id
      end
    end
  end
end
