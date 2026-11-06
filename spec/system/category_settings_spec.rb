# frozen_string_literal: true

# Discourse 2026.7 replaced the category editor. The old one saves the category model; the new one
# is a FormKit form that saves its own copy of custom_fields. Each Discourse version ships one of
# them, so each example runs on the version that has its editor.
RSpec.describe "Private topics category settings" do
  fab!(:admin)
  fab!(:category)
  fab!(:group)

  let(:category_page) { PageObjects::Pages::Category.new }
  let(:form) { PageObjects::Components::FormKit.new(".form-kit") }
  let(:toasts) { PageObjects::Components::Toasts.new }

  def old_editor?
    Rails.root.join("frontend/discourse/admin/components/edit-category-security.gjs").exist?
  end

  before do
    SiteSetting.private_topics_enabled = true
    sign_in(admin)
  end

  it "turns private topics on and off in the FormKit editor" do
    skip "this Discourse version has the old category editor" if old_editor?

    category_page.visit_security(category)
    form.field("custom_fields.private_topics_enabled").toggle
    groups = PageObjects::Components::SelectKit.new(".private-topics .group-chooser")
    groups.expand
    groups.select_row_by_name(group.name)
    groups.collapse
    category_page.save_settings

    expect(toasts).to have_success(I18n.t("js.saved"))
    category.reload
    expect(category.custom_fields["private_topics_enabled"]).to eq("t")
    expect(category.custom_fields["private_topics_allowed_groups"]).to eq(group.id.to_s)

    category_page.visit_security(category)
    form.field("custom_fields.private_topics_enabled").toggle
    category_page.save_settings

    expect(toasts).to have_success(I18n.t("js.saved"))
    expect(category.reload.custom_fields).not_to have_key("private_topics_enabled")
  end

  it "shows a stored \"f\" as private in the FormKit editor, as the server treats it" do
    skip "this Discourse version has the old category editor" if old_editor?
    category.upsert_custom_fields("private_topics_enabled" => "f")

    category_page.visit_security(category)

    # FormKit hides the input and draws its own checkmark.
    expect(page).to have_css(".private-topics .form-kit__control-checkbox:checked", visible: :all)
    expect(page).to have_css(".private-topics .group-chooser")
  end

  it "turns private topics on in the old editor" do
    skip "this Discourse version has the FormKit category editor" unless old_editor?

    category_page.visit_security(category)
    find(".category_private_topics_enabled input[type='checkbox']").click
    category_page.save_settings

    try_until_success do
      expect(category.reload.custom_fields["private_topics_enabled"]).to be_present
    end
  end
end
