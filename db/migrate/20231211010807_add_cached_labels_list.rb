class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    # Skip Cache module inclusion as it's no longer needed in acts-as-taggable-on 12.0.0
    # ActsAsTaggableOn::Taggable::Cache.included(Conversation)
  end
end
