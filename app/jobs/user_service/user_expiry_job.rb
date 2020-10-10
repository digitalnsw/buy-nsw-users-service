module UserService
  class UserExpiryJob < SharedModules::SlackReportingJob
    def perform
      reminded = 0
      about_to_expire = 0
      expired = 0

      User.where(uuid: nil, seller_id: nil, confirmed_at: nil).each do |user|

        next if user.confirmed? || user.suspended?

        d = (Date.today - user.confirmation_sent_at.to_date).to_i

        mailer = UserExpiryMailer.with(email: user.email, user: user)

        if d == 7
          mailer.user_confirmation_reminder_email.deliver_later unless user.opted_out?

          reminded += 1
        end

        if d == 12
          mailer.user_about_deletion_email.deliver_later unless user.opted_out?

          about_to_expire += 1
        end

        if d >= 14
          mailer.user_expired_email.deliver_later unless user.opted_out?
          user.update_column(:email, user.email + '_' + Time.now.to_i.to_s)
          user.destroy

          expired += 1
        end
      end

      # return the fields back to the slack message hook
      [
        {
          title: "Unconfirmed users receive reminder after 7 days",
          value: "#{reminded} users",
        },
        {
          title: "Users about to expire receive warning on day 12",
          value: "#{about_to_expire} users",
        },
        {
          title: "Unconfirmed users are expired after 14 days",
          value: "#{expired} users",
        },
      ]
    end
  end
end
