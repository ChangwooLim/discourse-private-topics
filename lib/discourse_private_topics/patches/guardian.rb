# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module Guardian
      def can_create_post_on_topic?(topic)
        allowed = super
        unless allowed
          return can_create_post_on_explicit_private_topic?(topic)
        end

        return false unless can_see_topic?(topic)

        DiscoursePrivateTopics.topic_reply_allowed?(topic, @user)
      end

      private

      def can_create_post_on_explicit_private_topic?(topic)
        return false unless DiscoursePrivateTopics.topic_reply_via_explicit_access?(topic, @user)
        return false if system_message_replies_disabled?(topic)
        return false if (topic.closed? || topic.archived?) && !trusted_to_reply_to_restricted_topic?(topic)
        return false unless can_create_post?(nil)

        true
      end

      def trusted_to_reply_to_restricted_topic?(topic)
        (authenticated? && @user.has_trust_level?(TrustLevel[4])) ||
          is_moderator? ||
          can_perform_action_available_to_group_moderators?(topic)
      end

      def system_message_replies_disabled?(topic)
        !SiteSetting.enable_system_message_replies? &&
          topic.respond_to?(:subtype) &&
          topic.subtype == "system_message"
      end
    end
  end
end
