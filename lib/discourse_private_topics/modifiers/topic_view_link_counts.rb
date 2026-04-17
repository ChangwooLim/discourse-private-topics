# frozen_string_literal: true

module DiscoursePrivateTopics
  module Modifiers
    module TopicViewLinkCounts
      module_function

      def call(link_counts)
        return link_counts unless DiscoursePrivateTopics.private_topics_enabled?

        category_ids = DiscoursePrivateTopics.filtered_category_ids(nil)
        return link_counts if category_ids.empty?

        topic_ids =
          link_counts.values.flatten.map do |link|
            next unless link.is_a?(Hash) && link[:internal] && link[:url].is_a?(String)

            match = link[:url].match(%r{/t/[^/]+/(\d+)(?:/\d+)?})
            match[1].to_i if match
          end.compact.uniq

        topic_category_map = Topic.where(id: topic_ids).pluck(:id, :category_id).to_h

        link_counts.each do |post_id, links|
          link_counts[post_id] =
            links.reject do |link|
              next false unless link.is_a?(Hash) && link[:internal] && link[:url].is_a?(String)

              match = link[:url].match(%r{/t/[^/]+/(\d+)(?:/\d+)?})
              next false unless match

              topic_id = match[1].to_i
              category_ids.include?(topic_category_map[topic_id])
            end
        end

        link_counts.delete_if { |_post_id, links| !links.is_a?(Array) || links.empty? }
        link_counts
      rescue => e
        Rails.logger.warn(
          "#{DiscoursePrivateTopics::PLUGIN_NAME}: topic_view_link_counts modifier failed: #{e.class} - #{e.message}",
        )
        link_counts
      end
    end
  end
end
