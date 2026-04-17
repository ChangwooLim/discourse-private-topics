# frozen_string_literal: true

require "rails_helper"

describe DiscoursePrivateTopics::AllowedUsersController do
  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_allowed_user_manager_groups = manager_group.id.to_s
    allow(PostCreator).to receive(:create!).and_return(double("post"))
  end

  fab!(:manager_group) { Fabricate(:group) }
  fab!(:manager_user) { Fabricate(:user) }
  fab!(:manager_membership) { Fabricate(:group_user, group: manager_group, user: manager_user) }

  fab!(:author) { Fabricate(:user) }
  fab!(:direct_user) { Fabricate(:user) }
  fab!(:outsider) { Fabricate(:user) }
  fab!(:admin_user) { Fabricate(:admin) }
  fab!(:shared_group) { Fabricate(:group) }
  fab!(:other_group) { Fabricate(:group) }
  fab!(:author_shared_membership) { Fabricate(:group_user, group: shared_group, user: author) }

  fab!(:regular_category) { Fabricate(:category) }
  fab!(:restricted_group) { Fabricate(:group) }
  fab!(:restricted_candidate) { Fabricate(:user) }

  fab!(:private_category) do
    category = Fabricate(:category)
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end

  fab!(:restricted_private_category) do
    category = Fabricate(:category)
    category.set_permissions(restricted_group.name => :full)
    category.save!
    category.upsert_custom_fields("private_topics_enabled" => "true")
    category
  end

  fab!(:private_topic) { Fabricate(:topic, category: private_category, user: author) }
  fab!(:regular_topic) { Fabricate(:topic, category: regular_category, user: author) }
  fab!(:restricted_private_topic) do
    Fabricate(:topic, category: restricted_private_category, user: author)
  end

  def parsed_entries
    response.parsed_body["private_topic_access_entries"] || []
  end

  it "lets the author replace the topic access set with users and groups" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: {
          users: [{ id: direct_user.id, access_level: "read" }],
          groups: [{ id: shared_group.id, access_level: "reply" }],
        }

    expect(response.status).to eq(200)
    expect(PrivateTopicAllowedUser.find_by(topic: private_topic, user: direct_user)&.access_level).to eq("read")
    expect(PrivateTopicAllowedGroup.find_by(topic: private_topic, group: shared_group)&.access_level).to eq("reply")
    expect(parsed_entries).to include(
      a_hash_including(
        "principal_type" => "user",
        "principal_id" => direct_user.id,
        "access_level" => "read",
      ),
      a_hash_including(
        "principal_type" => "group",
        "principal_id" => shared_group.id,
        "access_level" => "reply",
      ),
    )
    expect(PrivateTopicAccessEvent.where(topic: private_topic).pluck(:subject_type, :action, :new_access_level)).to include(
      ["user", "granted", "read"],
      ["group", "granted", "reply"],
    )
    expect(PostCreator).to have_received(:create!).with(
      Discourse.system_user,
      hash_including(
        archetype: Archetype.private_message,
        target_usernames: direct_user.username,
      ),
    ).once
  end

  it "keeps the legacy user_ids payload as reply access" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users", params: { user_ids: [direct_user.id] }

    expect(response.status).to eq(200)
    expect(PrivateTopicAllowedUser.find_by(topic: private_topic, user: direct_user)&.access_level).to eq("reply")
  end

  it "does not send a DM when the notification site setting is disabled" do
    SiteSetting.private_topics_send_access_granted_notifications = false
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }

    expect(response.status).to eq(200)
    expect(PrivateTopicAllowedUser.find_by(topic: private_topic, user: direct_user)&.access_level).to eq("reply")
    expect(PostCreator).not_to have_received(:create!)
  end

  it "lets manager group users replace the topic access set" do
    sign_in(manager_user)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }

    expect(response.status).to eq(200)
    expect(PrivateTopicAllowedUser.find_by(topic: private_topic, user: direct_user)&.access_level).to eq("reply")
  end

  it "lets admins manage access only when they can already see the topic" do
    sign_in(admin_user)

    SiteSetting.private_topics_admin_sees_all = false
    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }
    expect(response.status).to eq(403)

    SiteSetting.private_topics_admin_sees_all = true
    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }
    expect(response.status).to eq(200)
  end

  it "does not let explicit viewers manage access" do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_user,
      granted_by: author,
      access_level: "read",
    )
    sign_in(direct_user)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: outsider.id, access_level: "reply" }] }

    expect(response.status).to eq(403)
  end

  it "does not let outsiders manage access" do
    sign_in(outsider)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }

    expect(response.status).to eq(403)
  end

  it "rejects access lists on non-private categories" do
    sign_in(author)

    put "/private-topics/topics/#{regular_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }

    expect(response.status).to eq(400)
  end

  it "rejects users who cannot read the topic category" do
    sign_in(author)

    put "/private-topics/topics/#{restricted_private_topic.id}/allowed-users",
        params: { users: [{ id: restricted_candidate.id, access_level: "read" }] }

    expect(response.status).to eq(400)
    expect(response.parsed_body["errors"]).to include(
      I18n.t("private_topics.errors.users_without_category_access", usernames: restricted_candidate.username),
    )
  end

  it "returns validation errors for invalid groups and access levels" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { groups: [{ id: 999_999, access_level: "invalid" }] }

    expect(response.status).to eq(400)
    expect(response.parsed_body["errors"]).to include(
      I18n.t("private_topics.errors.invalid_access_level"),
    )
  end

  it "returns a validation error when the provided group id does not exist" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { groups: [{ id: 999_999, access_level: "reply" }] }

    expect(response.status).to eq(400)
    expect(response.parsed_body["errors"]).to include(
      I18n.t("private_topics.errors.invalid_group_ids", group_ids: "999999"),
    )
  end

  it "deduplicates repeated principals and keeps the highest requested access level" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: {
          users: [
            { id: direct_user.id, access_level: "read" },
            { id: direct_user.id, access_level: "reply" },
          ],
          groups: [
            { id: shared_group.id, access_level: "read" },
            { id: shared_group.id, access_level: "reply" },
          ],
        }

    expect(response.status).to eq(200)
    expect(PrivateTopicAllowedUser.where(topic: private_topic, user: direct_user).count).to eq(1)
    expect(PrivateTopicAllowedGroup.where(topic: private_topic, group: shared_group).count).to eq(1)
    expect(PrivateTopicAllowedUser.find_by(topic: private_topic, user: direct_user)&.access_level).to eq("reply")
    expect(PrivateTopicAllowedGroup.find_by(topic: private_topic, group: shared_group)&.access_level).to eq("reply")
  end

  it "rejects non-admin attempts to add groups they do not belong to" do
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: {
          groups: [{ id: other_group.id, access_level: "reply" }],
        }

    expect(response.status).to eq(400)
    expect(response.parsed_body["errors"]).to include(
      I18n.t("private_topics.errors.unauthorized_groups", group_names: other_group.name),
    )
  end

  it "records removals and access level changes without sending new direct-user DMs" do
    PrivateTopicAllowedUser.create!(
      topic: private_topic,
      user: direct_user,
      granted_by: author,
      access_level: "reply",
    )
    PrivateTopicAllowedGroup.create!(
      topic: private_topic,
      group: shared_group,
      granted_by: author,
      access_level: "reply",
    )
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "read" }], groups: [] }

    expect(response.status).to eq(200)
    expect(PrivateTopicAccessEvent.where(topic: private_topic).pluck(:subject_type, :action)).to include(
      ["user", "access_level_changed"],
      ["group", "removed"],
    )
    expect(PostCreator).not_to have_received(:create!)
  end

  it "returns access history to admins only" do
    SiteSetting.private_topics_admin_sees_all = true
    PrivateTopicAccessEvent.create!(
      topic: private_topic,
      actor: author,
      subject_type: "user",
      subject_id: direct_user.id,
      action: "granted",
      previous_access_level: nil,
      new_access_level: "read",
      metadata: { subject_label: direct_user.username, actor_username: author.username },
    )

    sign_in(admin_user)
    get "/private-topics/topics/#{private_topic.id}/access-history"

    expect(response.status).to eq(200)
    expect(response.parsed_body["private_topic_access_history"]).to include(
      a_hash_including(
        "subject_type" => "user",
        "subject_id" => direct_user.id,
        "action" => "granted",
        "new_access_level" => "read",
      ),
    )
  end

  it "rejects access history requests from non-admin managers" do
    sign_in(author)

    get "/private-topics/topics/#{private_topic.id}/access-history"

    expect(response.status).to eq(403)
  end

  it "returns a validation error when access storage is unavailable" do
    allow(DiscoursePrivateTopics).to receive(:access_entries_storage_ready?).and_return(false)
    sign_in(author)

    put "/private-topics/topics/#{private_topic.id}/allowed-users",
        params: { users: [{ id: direct_user.id, access_level: "reply" }] }

    expect(response.status).to eq(400)
    expect(response.parsed_body["errors"]).to include(
      I18n.t("private_topics.errors.allowed_users_storage_unavailable"),
    )
  end
end
