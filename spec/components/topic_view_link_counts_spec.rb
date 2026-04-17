# frozen_string_literal: true

require "rails_helper"

describe DiscoursePrivateTopics::Modifiers::TopicViewLinkCounts do
  before { SiteSetting.private_topics_enabled = true }

  fab!(:author) { Fabricate(:user) }
  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end
  fab!(:regular_category) { Fabricate(:category) }
  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }
  fab!(:regular_topic) { Fabricate(:topic, category: regular_category, user: author) }

  it "filters out backlinks to private-category topics" do
    result =
      described_class.call(
        1 => [
          { internal: true, url: "/t/private/#{private_topic.id}" },
          { internal: true, url: "/t/regular/#{regular_topic.id}" },
        ],
      )

    expect(result[1].length).to eq(1)
    expect(result[1][0][:url]).to eq("/t/regular/#{regular_topic.id}")
  end
end
