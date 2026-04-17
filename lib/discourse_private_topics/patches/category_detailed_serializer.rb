# frozen_string_literal: true

module DiscoursePrivateTopics
  module Patches
    module CategoryDetailedSerializer
      def include_displayable_topics?
        displayable_topics.present? && custom_fields["private_topics_enabled"] != "t"
      end
    end
  end
end
