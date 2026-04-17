# frozen_string_literal: true

class PrivateTopicAllowedGroup < ActiveRecord::Base
  belongs_to :topic
  belongs_to :group
  belongs_to :granted_by, class_name: "User"

  before_validation :set_default_access_level

  validates :topic_id, uniqueness: { scope: :group_id }
  validates :access_level, inclusion: { in: ->(_) { DiscoursePrivateTopics::ACCESS_LEVELS.keys } }

  private

  def set_default_access_level
    self.access_level = DiscoursePrivateTopics::REPLY_ACCESS_LEVEL if access_level.blank?
  end
end
