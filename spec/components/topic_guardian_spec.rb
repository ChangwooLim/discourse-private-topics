# frozen_string_literal: true

require "rails_helper"

describe TopicGuardian do
  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
  end

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:author) { Fabricate(:user) }
  fab!(:direct_read_user) { Fabricate(:user) }
  fab!(:direct_reply_user) { Fabricate(:user) }
  fab!(:group_read_group) { Fabricate(:group) }
  fab!(:group_read_user) { Fabricate(:user) }
  fab!(:group_read_membership) { Fabricate(:group_user, group: group_read_group, user: group_read_user) }
  fab!(:group_reply_group) { Fabricate(:group) }
  fab!(:group_reply_user) { Fabricate(:user) }
  fab!(:group_reply_membership) do
    Fabricate(:group_user, group: group_reply_group, user: group_reply_user)
  end
  fab!(:outsider) { Fabricate(:user) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end

  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }

  before do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_read_user,
      granted_by: author,
      access_level: "read",
    )
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_reply_user,
      granted_by: author,
      access_level: "reply",
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: group_read_group,
      granted_by: author,
      access_level: "read",
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: group_reply_group,
      granted_by: author,
      access_level: "reply",
    )
  end

  it "lets read-only viewers see the topic without edit or reply permissions" do
    guardian = Guardian.new(direct_read_user)

    expect(guardian.can_see_topic?(private_topic)).to eq(true)
    expect(guardian.can_edit_topic?(private_topic)).to eq(false)
    expect(guardian.can_edit_post?(private_topic.first_post)).to eq(false)
    expect(guardian.can_create_post_on_topic?(private_topic)).to eq(false)
  end

  it "lets direct and dynamic-group reply viewers reply" do
    expect(Guardian.new(direct_reply_user).can_create_post_on_topic?(private_topic)).to eq(true)
    expect(Guardian.new(group_reply_user).can_create_post_on_topic?(private_topic)).to eq(true)
  end

  it "lets dynamic-group read-only viewers see without reply permission" do
    guardian = Guardian.new(group_read_user)

    expect(guardian.can_see_topic?(private_topic)).to eq(true)
    expect(guardian.can_create_post_on_topic?(private_topic)).to eq(false)
  end

  it "lets manager group members view the topic" do
    expect(Guardian.new(manager_user).can_see_topic?(private_topic)).to eq(true)
  end

  it "still hides the topic from unrelated users" do
    expect(Guardian.new(outsider).can_see_topic?(private_topic)).to eq(false)
  end
end
