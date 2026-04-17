# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module FollowNotificationHandler
      def handle
        hidden_category_ids = DiscoursePrivateTopics.filtered_category_ids(nil)

        if post&.topic&.category_id && hidden_category_ids.include?(post.topic.category_id)
          return
        end

        super
      end
    end
  end
end
