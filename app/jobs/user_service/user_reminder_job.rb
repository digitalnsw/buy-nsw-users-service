module UserService
  class UserReminderJob < SharedModules::SlackReportingJob
    def perform
      reminded = 0

      # Unconfirmed users who are not invited as team member or imported from tenders
      User.where(uuid: nil, seller_id: nil).where.not(confirmed_at: nil).each do |user|

        next unless user.is_seller? && user.seller_id.nil?

        d = (Date.today - user.confirmed_at.to_date).to_i

        next if d <= 0 || d % 28 != 0

        mailer = UserReminderMailer.with(email: user.email)

        mailer.supplier_register_email.deliver_later

        reminded += 1
      end

      [
        {
          title: "Users who have not started their application, receive reminders every 28 days",
          value: "#{reminded} reminders sent",
        },
      ]
    end
  end
end
