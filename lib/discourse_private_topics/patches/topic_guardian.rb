# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module TopicGuardian
      def can_see_topic?(topic, hide_deleted = true)
        allowed = super
        return false unless allowed

        DiscoursePrivateTopics.topic_visible_to_user?(topic, @user)
      end
    end
  end
end
