# frozen_string_literal: true

require "rails_helper"

describe TopicQuery do
  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
  end

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:shared_group) { Fabricate(:group) }
  fab!(:shared_group_user) { Fabricate(:user) }
  fab!(:shared_group_membership) { Fabricate(:group_user, group: shared_group, user: shared_group_user) }

  fab!(:author) { Fabricate(:user) }
  fab!(:direct_read_user) { Fabricate(:user) }
  fab!(:outsider) { Fabricate(:user) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end

  fab!(:regular_category) { Fabricate(:category) }
  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }
  fab!(:group_private_topic) { Fabricate(:topic, category: private_category, user: author) }
  fab!(:regular_topic) { Fabricate(:topic, category: regular_category, user: author) }

  before do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_read_user,
      granted_by: author,
      access_level: "read",
    )
    PrivateTopicAllowedGroup.create!(
      topic: group_private_topic,
      group: shared_group,
      granted_by: author,
      access_level: "reply",
    )
  end

  it "keeps explicitly granted topics visible in latest lists" do
    expect(TopicQuery.new(direct_read_user).list_latest.topics.map(&:id)).to include(
      private_topic.id,
      regular_topic.id,
    )
    expect(TopicQuery.new(direct_read_user).list_latest.topics.map(&:id)).not_to include(group_private_topic.id)
  end

  it "shows group-granted private topics to current group members" do
    expect(TopicQuery.new(shared_group_user).list_latest.topics.map(&:id)).to include(
      group_private_topic.id,
      regular_topic.id,
    )
    expect(TopicQuery.new(shared_group_user).list_latest.topics.map(&:id)).not_to include(private_topic.id)
  end

  it "shows private topics to manager group members across the category" do
    expect(TopicQuery.new(manager_user).list_latest.topics.map(&:id)).to include(
      private_topic.id,
      group_private_topic.id,
      regular_topic.id,
    )
  end

  it "keeps unrelated users out of private topics" do
    expect(TopicQuery.new(outsider).list_latest.topics.map(&:id)).to include(regular_topic.id)
    expect(TopicQuery.new(outsider).list_latest.topics.map(&:id)).not_to include(
      private_topic.id,
      group_private_topic.id,
    )
  end
end
