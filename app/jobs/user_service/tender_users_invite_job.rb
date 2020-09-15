module UserService
  class TenderUsersInviteJob < SharedModules::SlackReportingJob
    def perform
      reminded = 0
      now = Time.now.getlocal('+11:00')
      if now.wday.in?(1..5) && now.hour.in?(9..14)
        User.where.not(uuid: nil).
             where(confirmed_at: nil, opted_out: false, suspended: false).
             order(:confirmation_sent_at).limit(120).each do |user|

          next if user.confirmation_sent_at > 4.weeks.ago

          user.update_columns(confirmation_token: SecureRandom.base58(20), confirmation_sent_at: Time.now)

          mailer = SellerInvitationMailer.with(user: user)
          mailer.tender_invitation_email.deliver_later

          reminded += 1
        end
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
