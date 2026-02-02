class Contacts::SyncAttributes
  attr_reader :contact

  def initialize(contact)
    @contact = contact
  end

  def perform
    update_contact_location_and_country_code
    set_contact_type
  end

  private

  def update_contact_location_and_country_code
    # Only sync from additional_attributes if values weren't explicitly set via API
    # This allows API updates to take precedence
    @contact.location = @contact.additional_attributes['city'] if @contact.location.blank?
    @contact.country_code = @contact.additional_attributes['country'] if @contact.country_code.blank?
  end

  def set_contact_type
    #  If the contact is already a lead or customer then do not change the contact type
    return unless @contact.contact_type == 'visitor'
    # If the contact has an email or phone number or social details( facebook_user_id, instagram_user_id, etc) then it is a lead
    # If contact is from external channel like facebook, instagram, whatsapp, etc then it is a lead
    return unless @contact.email.present? || @contact.phone_number.present? || social_details_present?

    @contact.contact_type = 'lead'
  end

  def social_details_present?
    @contact.additional_attributes.keys.any? do |key|
      key.start_with?('social_') && @contact.additional_attributes[key].present?
    end
  end
end
