# frozen_string_literal: true

class PrivateTopicAccessEvent < ActiveRecord::Base
  belongs_to :topic
  belongs_to :actor, class_name: "User"

  validates :subject_type, inclusion: { in: %w[user group] }
  validates :action, inclusion: { in: ->(_) { DiscoursePrivateTopics::ACCESS_EVENT_ACTIONS } }
end
