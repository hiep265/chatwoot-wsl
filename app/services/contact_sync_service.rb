# frozen_string_literal: true

# Service để xử lý update từ AI schema
# Phân tách contact fields và custom attributes
class ContactSyncService
  # Các trường thuộc bảng contacts
  CONTACT_FIELDS = %w[
    name email phone_number location country_code
    last_name middle_name identifier
  ].freeze
  
  # Các trường custom attributes (lưu trong custom_attributes JSONB)
  CUSTOM_ATTR_FIELDS = %w[
    company_name preferred_payment customer_type 
    preferred_language birth_date
  ].freeze
  
  def initialize(contact)
    @contact = contact
  end
  
  # Nhận JSON từ AI và xử lý update
  # @param data [Hash] JSON từ AI
  # @return [Hash] kết quả update
  def update_from_ai_schema(data)
    return { success: false, error: 'No data provided' } if data.blank?
    
    # Tách data thành 2 phần
    contact_updates = {}
    custom_updates = {}
    
    data.each do |key, value|
      key_str = key.to_s
      if CONTACT_FIELDS.include?(key_str)
        contact_updates[key_str] = value
      elsif CUSTOM_ATTR_FIELDS.include?(key_str)
        custom_updates[key_str] = value
      else
        # Unknown field - lưu vào additional_attributes
        custom_updates[key_str] = value
      end
    end
    
    results = {
      success: true,
      contact_updated: false,
      custom_attrs_updated: false,
      memories_created: [],
      errors: []
    }
    
    ActiveRecord::Base.transaction do
      # 1. Update contact fields
      if contact_updates.any?
        old_values = contact_updates.transform_keys { |k| "#{k}_was" }
                          .transform_values { |k| @contact.send(k) rescue nil }
        
        if @contact.update(contact_updates)
          results[:contact_updated] = true
          results[:contact_changes] = contact_updates
          
          # Tạo memory ghi lại thay đổi (audit trail)
          contact_updates.each do |field, new_value|
            old_value = @contact.send("#{field}_before_last_save") rescue nil
            next if old_value == new_value
            
            memory_content = generate_change_description(field, old_value, new_value)
            memory = @contact.contact_memories.create!(
              content: memory_content,
              category: 'context',
              metadata: {
                source: 'ai_contact_update',
                field: field,
                old_value: old_value,
                new_value: new_value,
                changed_at: Time.now.iso8601
              },
              account: @contact.account
            )
            results[:memories_created] << memory.id
          end
        else
          results[:errors] += @contact.errors.full_messages
          results[:success] = false
        end
      end
      
      # 2. Update custom attributes
      if custom_updates.any? && results[:success]
        current_custom = @contact.custom_attributes || {}
        updated_custom = current_custom.merge(custom_updates.stringify_keys)
        
        if @contact.update(custom_attributes: updated_custom)
          results[:custom_attrs_updated] = true
          results[:custom_changes] = custom_updates
        else
          results[:errors] += @contact.errors.full_messages
          results[:success] = false
        end
      end
    end
    
    results
  rescue StandardError => e
    Rails.logger.error "ContactSyncService error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    { success: false, error: e.message }
  end
  
  # Lấy thông tin contact hiện tại để trả về cho AI
  def get_contact_info
    {
      id: @contact.id,
      name: @contact.name,
      email: @contact.email,
      phone_number: @contact.phone_number,
      location: @contact.location,
      country_code: @contact.country_code,
      company_name: @contact.custom_attributes&.dig('company_name'),
      custom_attributes: @contact.custom_attributes,
      additional_attributes: @contact.additional_attributes,
      created_at: @contact.created_at,
      last_activity_at: @contact.last_activity_at
    }
  end
  
  private
  
  def generate_change_description(field, old_val, new_val)
    field_labels = {
      'name' => 'tên',
      'email' => 'email',
      'phone_number' => 'số điện thoại',
      'location' => 'địa chỉ',
      'country_code' => 'quốc gia',
      'last_name' => 'họ',
      'middle_name' => 'tên đệm',
      'identifier' => 'mã định danh'
    }
    
    label = field_labels[field] || field
    
    if old_val.present?
      "Cập nhật #{label}: thay đổi từ '#{old_val}' thành '#{new_val}'"
    else
      "Thêm #{label}: #{new_val}"
    end
  end
end
