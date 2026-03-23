module Aftercare
  class GmailDeliveryCapability
    def self.smtp_ready?
      ENV.fetch('SMTP_ADDRESS', nil).present? || Rails.env.development?
    end
  end
end
