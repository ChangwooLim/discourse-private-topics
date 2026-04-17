# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module Topic
      def recent(max = 10)
        category_ids = DiscoursePrivateTopics.filtered_category_ids(nil)
        relation = super

        category_ids.empty? ? relation : relation.where.not(category_id: category_ids).limit(max)
      end

      def for_digest(user, since, opts = nil)
        relation = super
        DiscoursePrivateTopics.filter_visible_topics(relation, user)
      end

      def similar_to(title, raw, user = nil)
        relation = super
        DiscoursePrivateTopics.filter_visible_topics(relation, user)
      end
    end
  end
end
