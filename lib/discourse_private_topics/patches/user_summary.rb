# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module UserSummary
      def topics
        DiscoursePrivateTopics.filter_visible_topics(super, @guardian&.user)
      end

      def replies
        DiscoursePrivateTopics.filter_visible_topics(super, @guardian&.user)
      end

      def links
        DiscoursePrivateTopics.filter_visible_topics(super, @guardian&.user)
      end
    end
  end
end
