# frozen_string_literal: true

RSpec.describe "Private topic access modal" do
  fab!(:author, :user)
  fab!(:reader, :user)
  fab!(:category) do
    Fabricate(:category).tap { |c| c.upsert_custom_fields("private_topics_enabled" => "t") }
  end
  fab!(:topic) { Fabricate(:topic, category:, user: author) }
  fab!(:first_post) { Fabricate(:post, topic:, user: author) }

  let(:topic_page) { PageObjects::Pages::Topic.new }

  before do
    SiteSetting.private_topics_enabled = true
    SiteSetting.private_topics_send_access_granted_notifications = false
  end

  it "lets the author grant a user access from the first post" do
    sign_in(author)
    topic_page.visit_topic(topic)

    find("#post_1 .post-action-menu__private-topic-manage-access").click
    expect(page).to have_css(".d-modal .private-topic-access-modal__section")

    users = PageObjects::Components::SelectKit.new(".d-modal .user-chooser")
    users.expand
    users.search(reader.username)
    users.select_row_by_value(reader.username)
    users.collapse
    expect(page).to have_css(".private-topic-access-modal__table", text: reader.username)

    find(".d-modal__footer .btn-primary").click

    try_until_success do
      # The modal adds people with reply access; the table lets the author lower it to read.
      expect(PrivateTopicAllowedUser.find_by(topic:, user: reader)&.access_level).to eq("reply")
    end
  end

  it "does not offer the button to a reader with explicit access" do
    PrivateTopicAllowedUser.create!(topic:, user: reader, granted_by: author, access_level: "read")
    sign_in(reader)
    topic_page.visit_topic(topic)

    expect(page).to have_css("#post_1")
    expect(page).to have_no_css("#post_1 .post-action-menu__private-topic-manage-access")
  end
end
