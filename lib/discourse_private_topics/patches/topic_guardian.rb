# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module TopicGuardian
      def can_see_topic?(topic, _hide_deleted = true)
        allowed = super
        unless allowed
          return DiscoursePrivateTopics.topic_visible_via_explicit_access?(topic, @user)
        end

        DiscoursePrivateTopics.topic_visible_to_user?(topic, @user)
      end
    end
  end
end
