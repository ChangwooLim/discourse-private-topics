# frozen_string_literal: true

require "rails_helper"

describe Topic do
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
  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author, title: "Digest Alpha") }
  fab!(:group_private_topic) do
    Fabricate(:topic, category: private_category, user: author, title: "Digest Beta")
  end
  fab!(:regular_topic) { Fabricate(:topic, category: regular_category, user: author, title: "Digest Gamma") }

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

  it "filters digest topics with direct and dynamic grants" do
    expect(Topic.for_digest(direct_read_user, 1.day.ago).pluck(:id)).to include(
      private_topic.id,
      regular_topic.id,
    )
    expect(Topic.for_digest(shared_group_user, 1.day.ago).pluck(:id)).to include(
      group_private_topic.id,
      regular_topic.id,
    )
    expect(Topic.for_digest(outsider, 1.day.ago).pluck(:id)).not_to include(
      private_topic.id,
      group_private_topic.id,
    )
  end

  it "keeps contextless recent topics conservative" do
    expect(Topic.recent(10).pluck(:id)).to include(regular_topic.id)
    expect(Topic.recent(10).pluck(:id)).not_to include(private_topic.id, group_private_topic.id)
  end

  it "keeps private topics visible in digest for manager group members" do
    expect(Topic.for_digest(manager_user, 1.day.ago).pluck(:id)).to include(
      private_topic.id,
      group_private_topic.id,
      regular_topic.id,
    )
  end
end
