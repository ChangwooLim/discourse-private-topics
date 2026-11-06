import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { i18n } from "discourse-i18n";
import GroupChooser from "select-kit/components/group-chooser";

// The server treats a category as private when it stores any private_topics_enabled value,
// including the "f" that older Discourse versions wrote for an unchecked box.
function isStored(value) {
  return value !== undefined && value !== null && value !== "";
}

// The category editor in Discourse 2026.7 and later passes a FormKit form to this outlet. It saves
// the form's copy of custom_fields and drops changes made to the category model, so this connector
// writes through the form. Unchecking writes "", which makes the server delete the field.
export default class PrivateTopicsForm extends Component {
  static shouldRender(args) {
    return Boolean(args.form);
  }

  @service site;
  @service siteSettings;

  @tracked
  enabled = isStored(
    this.args.outletArgs.category.custom_fields?.private_topics_enabled
  );

  @tracked
  selectedGroups = this.groupNamesFor(
    this.args.outletArgs.category.custom_fields?.private_topics_allowed_groups
  );

  get availableGroups() {
    return (this.site.groups || [])
      .filter((group) => group.id !== 0)
      .map((group) => group.name);
  }

  get showWarning() {
    const everyone = (this.site.groups || []).find((group) => group.id === 0);
    const everyoneName = everyone?.name || "everyone";
    return (this.args.outletArgs.category.permissions || []).some(
      (permission) => permission.group_name === everyoneName
    );
  }

  groupNamesFor(storedIds) {
    const ids = (storedIds || "")
      .split(",")
      .filter(Boolean)
      .map((id) => parseInt(id, 10));
    return (this.site.groups || [])
      .filter((group) => ids.includes(group.id))
      .map((group) => group.name);
  }

  @action
  async setEnabled(checked, { set, name }) {
    this.enabled = checked;
    await set(name, checked ? "t" : "");
  }

  @action
  setGroups(field, groupNames) {
    this.selectedGroups = groupNames;
    const ids = (this.site.groups || [])
      .filter((group) => groupNames.includes(group.name))
      .map((group) => group.id);
    field.set(ids.join(","));
  }

  <template>
    {{#if this.siteSettings.private_topics_enabled}}
      <@outletArgs.form.Section
        class="category-custom-settings-outlet private-topics"
        @title={{i18n "category.private_topics.title"}}
      >
        <@outletArgs.form.Object @name="custom_fields" as |customFields|>
          <customFields.Field
            @format="max"
            @name="private_topics_enabled"
            @onSet={{this.setEnabled}}
            @title={{i18n "category.private_topics.enabled"}}
            @type="checkbox"
            as |field|
          >
            <field.Control checked={{this.enabled}} />
          </customFields.Field>

          {{#if this.enabled}}
            {{#if this.showWarning}}
              <@outletArgs.form.Alert @type="warning">
                {{htmlSafe (i18n "category.private_topics.warning")}}
              </@outletArgs.form.Alert>
            {{/if}}

            <customFields.Field
              @description={{i18n "category.private_topics.topic_access_help"}}
              @format="large"
              @name="private_topics_allowed_groups"
              @title={{i18n "category.private_topics.allowed_groups_description"}}
              @type="custom"
              as |field|
            >
              <field.Control>
                <GroupChooser
                  @content={{this.availableGroups}}
                  @nameProperty={{null}}
                  @onChange={{fn this.setGroups field}}
                  @value={{this.selectedGroups}}
                  @valueProperty={{null}}
                />
              </field.Control>
            </customFields.Field>
          {{/if}}
        </@outletArgs.form.Object>
      </@outletArgs.form.Section>
    {{/if}}
  </template>
}
