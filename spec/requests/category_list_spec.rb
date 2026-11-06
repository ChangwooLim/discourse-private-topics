# frozen_string_literal: true

require "rails_helper"

# The category page lists each category's featured topics, which core picks with Topic.secured
# alone, so the plugin hides that list for private categories in CategoryDetailedSerializer.
describe "category list featured topics" do
  fab!(:author, :user)
  fab!(:outsider, :user)

  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.desktop_category_page_style = "categories_with_featured_topics"
  end

  # The values found in a live site: "t" from the old admin UI, "true" from the API, and the "f"
  # that older Discourse versions stored for an unchecked box, which the plugin still treats as
  # private (DiscoursePrivateTopics.private_category_ids reads any stored value).
  %w[t true f].each do |stored|
    it "does not list a private topic when the category stores #{stored.inspect}" do
      category = Fabricate(:category)
      category.upsert_custom_fields("private_topics_enabled" => stored)
      topic = Fabricate(:topic, category:, user: author, title: "Private featured topic #{stored}")
      Fabricate(:post, topic:, user: author)
      CategoryFeaturedTopic.feature_topics_for(category)
      expect(CategoryFeaturedTopic.where(category:).pluck(:topic_id)).to include(topic.id)

      sign_in(outsider)
      get "/categories.json"

      expect(response.status).to eq(200)
      listed =
        response.parsed_body.dig("category_list", "categories").find { |c| c["id"] == category.id }
      expect(listed).to be_present
      expect(Array(listed["topics"]).map { |t| t["id"] }).not_to include(topic.id)
    end
  end
end
