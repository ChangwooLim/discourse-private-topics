# frozen_string_literal: true

require "rails_helper"

describe Search do
  before do
    SearchIndexer.enable
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
  end

  after { SearchIndexer.disable }

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:category_group) { Fabricate(:group) }
  fab!(:category_group_user) { Fabricate(:user) }
  fab!(:category_group_membership) do
    Fabricate(:group_user, group: category_group, user: category_group_user)
  end

  fab!(:shared_group) { Fabricate(:group) }
  fab!(:shared_group_user) { Fabricate(:user) }
  fab!(:shared_group_membership) { Fabricate(:group_user, group: shared_group, user: shared_group_user) }

  fab!(:author_one) { Fabricate(:user) }
  fab!(:author_two) { Fabricate(:user) }
  fab!(:direct_read_user) { Fabricate(:user) }
  fab!(:outsider) { Fabricate(:user) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category.upsert_custom_fields("private_topics_allowed_groups" => category_group.id.to_s)
    category
  end

  fab!(:regular_category) { Fabricate(:category) }

  it "filters search results while respecting direct access, dynamic groups, category groups, and managers" do
    private_topic_one = Fabricate(:topic, category: private_category, user: author_one)
    Fabricate(:post, topic: private_topic_one, raw: "Searchable FooBar one", user: author_one)

    private_topic_two = Fabricate(:topic, category: private_category, user: author_two)
    Fabricate(:post, topic: private_topic_two, raw: "Searchable FooBar two", user: author_two)

    regular_topic = Fabricate(:topic, category: regular_category, user: author_one)
    Fabricate(:post, topic: regular_topic, raw: "Searchable FooBar regular", user: author_one)

    PrivateTopicAllowedUser.create!(
      topic: private_topic_two,
      user: direct_read_user,
      granted_by: author_two,
      access_level: "read",
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic_one,
      group: shared_group,
      granted_by: author_one,
      access_level: "reply",
    )

    expect(Search.execute("FooBar", guardian: Guardian.new(direct_read_user)).posts.length).to eq(2)
    expect(Search.execute("FooBar", guardian: Guardian.new(shared_group_user)).posts.length).to eq(2)
    expect(Search.execute("FooBar", guardian: Guardian.new(category_group_user)).posts.length).to eq(3)
    expect(Search.execute("FooBar", guardian: Guardian.new(manager_user)).posts.length).to eq(3)
    expect(Search.execute("FooBar", guardian: Guardian.new(outsider)).posts.length).to eq(1)
  end

  it "allows admins to see everything only when the bypass setting is enabled" do
    admin_user = Fabricate(:admin)
    private_topic = Fabricate(:topic, category: private_category, user: author_one)
    Fabricate(:post, topic: private_topic, raw: "Searchable FooBar admin", user: author_one)

    SiteSetting.private_topics_admin_sees_all = true
    expect(Search.execute("FooBar", guardian: Guardian.new(admin_user)).posts.length).to eq(1)

    SiteSetting.private_topics_admin_sees_all = false
    expect(Search.execute("FooBar", guardian: Guardian.new(admin_user)).posts.length).to eq(0)
  end
end
