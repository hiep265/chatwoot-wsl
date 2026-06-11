class AddCustomAttributesToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :custom_attributes, :jsonb, default: {}, null: false
  end
end
