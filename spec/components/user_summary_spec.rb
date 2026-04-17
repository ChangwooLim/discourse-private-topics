# frozen_string_literal: true

require "rails_helper"

describe UserSummary do
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

  it "filters summary topics using direct and dynamic access grants" do
    direct_summary = UserSummary.new(author, Guardian.new(direct_read_user))
    group_summary = UserSummary.new(author, Guardian.new(shared_group_user))
    outsider_summary = UserSummary.new(author, Guardian.new(outsider))

    expect(direct_summary.topics.pluck(:id)).to include(private_topic.id, regular_topic.id)
    expect(direct_summary.topics.pluck(:id)).not_to include(group_private_topic.id)

    expect(group_summary.topics.pluck(:id)).to include(group_private_topic.id, regular_topic.id)
    expect(group_summary.topics.pluck(:id)).not_to include(private_topic.id)

    expect(outsider_summary.topics.pluck(:id)).not_to include(private_topic.id, group_private_topic.id)
  end

  it "shows private topics to manager group members in summaries" do
    manager_summary = UserSummary.new(author, Guardian.new(manager_user))

    expect(manager_summary.topics.pluck(:id)).to include(
      private_topic.id,
      group_private_topic.id,
      regular_topic.id,
    )
  end
end
