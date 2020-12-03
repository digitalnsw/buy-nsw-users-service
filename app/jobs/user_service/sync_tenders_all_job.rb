module UserService
  class SyncTendersAllJob < SharedModules::ApplicationJob
    def perform
      User.where("sync_pending = true or uuid is null").pluck(:id).each do |user_id|
        UserService::SyncTendersJob.perform_later user_id
      end
    end
  end
end
