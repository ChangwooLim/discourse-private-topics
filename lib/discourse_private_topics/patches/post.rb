# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module Post
      def self.prepended(base)
        base.scope :public_posts, lambda {
          posts = base.joins(:topic).where("topics.archetype <> ?", Archetype.private_message)
          private_category_ids = DiscoursePrivateTopics.private_category_ids

          if DiscoursePrivateTopics.private_topics_enabled? && private_category_ids.any?
            posts.where.not("topics.category_id IN (?)", private_category_ids)
          else
            posts
          end
        }
      end
    end
  end
end
