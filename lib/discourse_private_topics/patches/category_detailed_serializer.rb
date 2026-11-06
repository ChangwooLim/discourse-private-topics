# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module CategoryDetailedSerializer
      # Core picks a category's featured topics with Topic.secured alone, so hide them for every
      # category the plugin treats as private (any stored private_topics_enabled value). Checking
      # the serialized value for "t" listed the topics of categories that store "true" or "f".
      def include_displayable_topics?
        displayable_topics.present? && !DiscoursePrivateTopics.private_category_enabled?(object.id)
      end
    end
  end
end
