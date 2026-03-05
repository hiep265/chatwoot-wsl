# frozen_string_literal: true

# == Schema Information
#
# Table name: social_comments
#
#  id                 :bigint           not null, primary key
#  account_id         :bigint           not null
#  inbox_id           :bigint           not null
#  platform           :string           default("instagram"), not null
#  post_id            :string           not null
#  comment_id         :string           not null (unique)
#  parent_comment_id  :string
#  content            :text
#  author_name        :string
#  author_id          :string
#  author_avatar_url  :string
#  direction          :integer          default(0), not null
#  status             :integer          default(0), not null
#  source_reply_id    :string
#  post_caption       :string
#  post_media_url     :string
#  post_permalink     :string
#  post_like_count    :integer
#  post_comment_count :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class SocialComment < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  enum direction: { incoming: 0, outgoing: 1 }
  enum status: { pending: 0, replied: 1, resolved: 2 }

  validates :comment_id, presence: true, uniqueness: true
  validates :post_id, presence: true
  validates :platform, presence: true

  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_post, ->(post_id) { where(post_id: post_id) }
  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :incoming_comments, -> { where(direction: :incoming) }
  scope :outgoing_comments, -> { where(direction: :outgoing) }
  scope :recent_first, -> { order(created_at: :desc) }
end
