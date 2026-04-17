# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module DiscourseAiEmbeddingsSemanticSearch
      def search_for_topics(query, page = 1, hyde: true)
        posts = super
        return posts unless DiscoursePrivateTopics.private_topics_enabled?

        posts.reject { |post| !@guardian.can_see_topic?(post.topic) }
      end
    end
  end
end
