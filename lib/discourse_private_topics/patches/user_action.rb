# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module UserAction
      def apply_common_filters(builder, user_id, guardian, ignore_private_messages = false)
        builder = DiscoursePrivateTopics.filter_visible_topics(builder, guardian&.user, topics_table: "t")
        super(builder, user_id, guardian, ignore_private_messages)
      end
    end
  end
end
