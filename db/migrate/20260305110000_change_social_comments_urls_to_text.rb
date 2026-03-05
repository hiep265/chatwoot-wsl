# frozen_string_literal: true

class ChangeSocialCommentsUrlsToText < ActiveRecord::Migration[7.0]
  def change
    change_column :social_comments, :post_media_url, :text
    change_column :social_comments, :post_permalink, :text
    change_column :social_comments, :author_avatar_url, :text
  end
end