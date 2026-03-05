# frozen_string_literal: true

class CreateSocialComments < ActiveRecord::Migration[7.0]
  def change
    create_table :social_comments do |t|
      t.references :account, null: false, index: true
      t.references :inbox, null: false, index: true
      t.string :platform, null: false, default: 'instagram'
      t.string :post_id, null: false
      t.string :comment_id, null: false
      t.string :parent_comment_id
      t.text :content
      t.string :author_name
      t.string :author_id
      t.string :author_avatar_url
      t.integer :direction, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.string :source_reply_id
      t.string :post_caption
      t.string :post_media_url
      t.string :post_permalink
      t.integer :post_like_count
      t.integer :post_comment_count
      t.timestamps
    end

    add_index :social_comments, :comment_id, unique: true
    add_index :social_comments, %i[account_id post_id]
    add_index :social_comments, %i[account_id platform status]
  end
end
