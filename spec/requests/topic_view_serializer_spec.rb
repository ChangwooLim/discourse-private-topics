# frozen_string_literal: true

require "rails_helper"

describe "Private topic serializers" do
  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
  end

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:admin_user) { Fabricate(:admin) }
  fab!(:author) { Fabricate(:user) }
  fab!(:allowed_user) { Fabricate(:user) }
  fab!(:outsider) { Fabricate(:user) }
  fab!(:shared_group) { Fabricate(:group) }
  fab!(:author_shared_membership) { Fabricate(:group_user, group: shared_group, user: author) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end

  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }

  before do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: allowed_user,
      granted_by: author,
      access_level: "read",
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: shared_group,
      granted_by: author,
      access_level: "reply",
    )
  end

  it "serializes mixed access metadata for managers while keeping the legacy user list" do
    sign_in(author)

    get "/t/#{private_topic.slug}/#{private_topic.id}.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["can_manage_private_topic_access"]).to eq(true)
    expect(response.parsed_body["can_manage_private_topic_allowed_users"]).to eq(true)
    expect(response.parsed_body["can_view_private_topic_access_history"]).to eq(false)
    expect(response.parsed_body["private_topic_access_entries"]).to include(
      a_hash_including(
        "principal_type" => "user",
        "principal_id" => allowed_user.id,
        "access_level" => "read",
      ),
      a_hash_including(
        "principal_type" => "group",
        "principal_id" => shared_group.id,
        "access_level" => "reply",
      ),
    )
    expect(response.parsed_body["private_topic_manageable_groups"]).to eq(
      [
        a_hash_including("id" => shared_group.id, "name" => shared_group.name),
      ],
    )
    expect(response.parsed_body["private_topic_allowed_users"]).to include(
      a_hash_including("id" => allowed_user.id, "username" => allowed_user.username, "access_level" => "read"),
    )

    first_post = response.parsed_body.dig("post_stream", "posts", 0)
    expect(first_post["can_manage_private_topic_access"]).to eq(true)
    expect(first_post["private_topic_access_entries"]).to include(
      a_hash_including("principal_type" => "group", "principal_id" => shared_group.id),
    )
    expect(first_post["private_topic_allowed_users"]).to include(
      a_hash_including("id" => allowed_user.id, "access_level" => "read"),
    )
  end

  it "shows manager controls but keeps history admin-only for manager-group members" do
    sign_in(manager_user)

    get "/t/#{private_topic.slug}/#{private_topic.id}.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["can_manage_private_topic_access"]).to eq(true)
    expect(response.parsed_body["can_view_private_topic_access_history"]).to eq(false)
  end

  it "exposes history metadata to admins who can already see the topic" do
    SiteSetting.private_topics_admin_sees_all = true
    sign_in(admin_user)

    get "/t/#{private_topic.slug}/#{private_topic.id}.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["can_manage_private_topic_access"]).to eq(true)
    expect(response.parsed_body["can_view_private_topic_access_history"]).to eq(true)
    expect(response.parsed_body["private_topic_manageable_groups"]).to include(
      a_hash_including("id" => shared_group.id, "name" => shared_group.name),
    )

    first_post = response.parsed_body.dig("post_stream", "posts", 0)
    expect(first_post["can_view_private_topic_access_history"]).to eq(true)
  end

  it "hides access metadata from explicit viewers" do
    sign_in(allowed_user)

    get "/t/#{private_topic.slug}/#{private_topic.id}.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["can_manage_private_topic_access"]).to eq(false)
    expect(response.parsed_body["can_manage_private_topic_allowed_users"]).to eq(false)
    expect(response.parsed_body["can_view_private_topic_access_history"]).to eq(false)
    expect(response.parsed_body).not_to have_key("private_topic_access_entries")
    expect(response.parsed_body).not_to have_key("private_topic_manageable_groups")
    expect(response.parsed_body).not_to have_key("private_topic_allowed_users")

    first_post = response.parsed_body.dig("post_stream", "posts", 0)
    expect(first_post["can_manage_private_topic_access"]).to eq(false)
    expect(first_post).not_to have_key("private_topic_access_entries")
    expect(first_post).not_to have_key("private_topic_allowed_users")
  end

  it "keeps unrelated users out of the topic entirely" do
    sign_in(outsider)

    get "/t/#{private_topic.slug}/#{private_topic.id}.json"

    expect(response.status).to eq(404)
  end
end
