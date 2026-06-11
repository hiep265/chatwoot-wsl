# frozen_string_literal: true

class AiControl::ReplayUnansweredConversationsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    AiControl::ChatwootReplyReplayService.new.perform
  end
end
