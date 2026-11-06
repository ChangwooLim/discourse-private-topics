# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module DiscourseAiEmbeddingsSemanticSearch
      # Pass arguments through unchanged: discourse-ai added private_messages: in Discourse 2026.10.
      def search_for_topics(*args, **kwargs)
        posts = super
        return posts unless DiscoursePrivateTopics.private_topics_enabled?

        posts.reject { |post| !@guardian.can_see_topic?(post.topic) }
      end
    end
  end
end
