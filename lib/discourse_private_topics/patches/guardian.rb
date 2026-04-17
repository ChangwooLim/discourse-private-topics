# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module Guardian
      def can_create_post_on_topic?(topic)
        allowed = super
        return false unless allowed
        return false unless can_see_topic?(topic)

        DiscoursePrivateTopics.topic_reply_allowed?(topic, @user)
      end
    end
  end
end
