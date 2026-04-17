# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module TopicQuery
      module_function

      def filter(result, query)
        DiscoursePrivateTopics.filter_visible_topics(result, query&.guardian&.user)
      end
    end
  end
end
