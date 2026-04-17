# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module Search
      def execute(readonly_mode: @readonly_mode)
        super
        return @results unless DiscoursePrivateTopics.private_topics_enabled?

        @results.posts.select! { |post| @guardian.can_see_topic?(post.topic) }
        @results
      end
    end
  end
end
