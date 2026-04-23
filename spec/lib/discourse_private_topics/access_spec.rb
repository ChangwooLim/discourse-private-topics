# frozen_string_literal: true

require "rails_helper"

describe DiscoursePrivateTopics do
  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
  end

  fab!(:support_group) { Fabricate(:group) }
  fab!(:support_member) { Fabricate(:user) }
  fab!(:support_membership) { Fabricate(:group_user, group: support_group, user: support_member) }

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:direct_read_user) { Fabricate(:user) }
  fab!(:direct_reply_user) { Fabricate(:user) }
  fab!(:hybrid_user) { Fabricate(:user) }
  fab!(:outsider) { Fabricate(:user) }

  fab!(:group_read_group) { Fabricate(:group) }
  fab!(:group_read_user) { Fabricate(:user) }
  fab!(:group_read_membership) { Fabricate(:group_user, group: group_read_group, user: group_read_user) }

  fab!(:group_reply_group) { Fabricate(:group) }
  fab!(:group_reply_user) { Fabricate(:user) }
  fab!(:group_reply_membership) do
    Fabricate(:group_user, group: group_reply_group, user: group_reply_user)
  end
  fab!(:hybrid_membership) { Fabricate(:group_user, group: group_reply_group, user: hybrid_user) }

  fab!(:author) { Fabricate(:user) }
  fab!(:regular_category) { Fabricate(:category) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category.upsert_custom_fields("private_topics_allowed_groups" => support_group.id.to_s)
    category
  end

  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }
  fab!(:regular_topic) { Fabricate(:topic, category: regular_category, user: author) }

  before do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_read_user,
      granted_by: author,
      access_level: described_class::READ_ACCESS_LEVEL,
    )
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_reply_user,
      granted_by: author,
      access_level: described_class::REPLY_ACCESS_LEVEL,
    )
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: hybrid_user,
      granted_by: author,
      access_level: described_class::READ_ACCESS_LEVEL,
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: group_read_group,
      granted_by: author,
      access_level: described_class::READ_ACCESS_LEVEL,
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: group_reply_group,
      granted_by: author,
      access_level: described_class::REPLY_ACCESS_LEVEL,
    )
  end

  it "keeps the category group exemption and manager bypass" do
    expect(described_class.topic_visible_to_user?(private_topic, support_member)).to eq(true)
    expect(described_class.topic_visible_to_user?(private_topic, manager_user)).to eq(true)
    expect(described_class.can_manage_topic_access?(private_topic, manager_user)).to eq(true)
  end

  it "supports direct read and reply access levels" do
    expect(described_class.topic_visible_to_user?(private_topic, direct_read_user)).to eq(true)
    expect(described_class.topic_reply_allowed?(private_topic, direct_read_user)).to eq(false)

    expect(described_class.topic_visible_to_user?(private_topic, direct_reply_user)).to eq(true)
    expect(described_class.topic_reply_allowed?(private_topic, direct_reply_user)).to eq(true)
  end

  it "supports dynamic group access and higher effective access selection" do
    expect(described_class.topic_visible_to_user?(private_topic, group_read_user)).to eq(true)
    expect(described_class.topic_reply_allowed?(private_topic, group_read_user)).to eq(false)

    expect(described_class.topic_visible_to_user?(private_topic, group_reply_user)).to eq(true)
    expect(described_class.topic_reply_allowed?(private_topic, group_reply_user)).to eq(true)

    expect(described_class.topic_explicit_access_level(private_topic, hybrid_user)).to eq(
      described_class::REPLY_ACCESS_LEVEL,
    )
    expect(described_class.topic_reply_allowed?(private_topic, hybrid_user)).to eq(true)
  end

  it "does not let explicit viewers manage access" do
    expect(described_class.can_manage_topic_access?(private_topic, direct_read_user)).to eq(false)
    expect(described_class.can_manage_topic_access?(private_topic, group_reply_user)).to eq(false)
  end

  it "filters topic relations for direct viewers, group viewers, and outsiders" do
    relation = Topic.where(id: [private_topic.id, regular_topic.id])

    expect(described_class.filter_visible_topics(relation, direct_read_user).pluck(:id)).to contain_exactly(
      private_topic.id,
      regular_topic.id,
    )
    expect(described_class.filter_visible_topics(relation, group_reply_user).pluck(:id)).to contain_exactly(
      private_topic.id,
      regular_topic.id,
    )
    expect(described_class.filter_visible_topics(relation, outsider).pluck(:id)).to contain_exactly(
      regular_topic.id,
    )
  end

  it "treats anonymous guardian users as non-members without raising" do
    anonymous_user = Guardian.new(nil).instance_variable_get(:@user)
    relation = Topic.where(id: [private_topic.id, regular_topic.id])

    expect(described_class.filtered_category_ids(anonymous_user)).to contain_exactly(private_category.id)
    expect(described_class.topic_visible_to_user?(private_topic, anonymous_user)).to eq(false)
    expect(described_class.filter_visible_topics(relation, anonymous_user).pluck(:id)).to contain_exactly(
      regular_topic.id,
    )
  end

  it "updates group-based visibility dynamically as memberships change" do
    expect(described_class.topic_visible_to_user?(private_topic, group_reply_user)).to eq(true)

    group_reply_membership.destroy!

    expect(described_class.topic_visible_to_user?(private_topic, group_reply_user)).to eq(false)
    expect(described_class.topic_reply_allowed?(private_topic, group_reply_user)).to eq(false)
  end
end
