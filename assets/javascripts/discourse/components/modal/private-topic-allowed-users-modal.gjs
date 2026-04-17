import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import GroupChooser from "select-kit/components/group-chooser";
import UserChooser from "select-kit/components/user-chooser";

export default class PrivateTopicAllowedUsersModal extends Component {
  @service site;

  @tracked accessEntries = [];
  @tracked selectedUsernames = [];
  @tracked selectedGroupNames = [];
  @tracked saving = false;
  @tracked error = null;
  @tracked successMessage = null;
  @tracked activeTab = "access";
  @tracked historyEvents = null;
  @tracked historyLoading = false;
  @tracked historyError = null;

  constructor() {
    super(...arguments);
    this.accessEntries = this.normalizeEntries(this.currentEntries);
  }

  get post() {
    return this.args.model.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get topicId() {
    return this.topic?.id || this.post?.topic_id;
  }

  get topicAuthorUsername() {
    return this.topic?.details?.created_by?.username || this.topic?.created_by?.username;
  }

  get excludedUsernames() {
    return [this.topicAuthorUsername].filter(Boolean);
  }

  get title() {
    return i18n("private_topics.allowed_users.modal_title");
  }

  get currentEntries() {
    return this.post?.private_topic_access_entries || this.post?.private_topic_allowed_users || [];
  }

  get canViewHistory() {
    return this.post?.can_view_private_topic_access_history || this.topic?.can_view_private_topic_access_history;
  }

  get hasHistoryEvents() {
    return Array.isArray(this.historyEvents) && this.historyEvents.length > 0;
  }

  get availableGroups() {
    return this.manageableGroups.map((group) => group.name).filter(Boolean);
  }

  get manageableGroups() {
    const manageableGroups =
      this.post?.private_topic_manageable_groups || this.topic?.private_topic_manageable_groups;

    if (manageableGroups) {
      return manageableGroups;
    }

    return (this.site.groups || [])
      .filter((group) => group.id !== 0)
      .map((group) => ({
        id: group.id,
        name: group.name,
        full_name: group.full_name,
      }));
  }

  get sortedAccessEntries() {
    return [...this.accessEntries].sort((left, right) => {
      if (left.principal_type !== right.principal_type) {
        return left.principal_type.localeCompare(right.principal_type);
      }

      return left.label.localeCompare(right.label);
    });
  }

  get isAccessTabActive() {
    return this.activeTab === "access";
  }

  get isHistoryTabActive() {
    return this.activeTab === "history";
  }

  normalizeEntries(entries) {
    return (entries || []).map((entry) => this.normalizeEntry(entry));
  }

  normalizeEntry(entry) {
    const principalType = entry.principal_type || "user";
    const principalId = entry.principal_id ?? entry.id ?? null;
    const username = entry.username || null;
    const groupName = entry.group_name || entry.name || null;
    const name = entry.name || null;
    const accessLevel = entry.access_level || "reply";
    const clientKey =
      principalType === "group"
        ? `group:${principalId ?? groupName}`
        : `user:${principalId ?? username}`;

    return {
      clientKey,
      principal_type: principalType,
      principal_id: principalId,
      username,
      group_name: groupName,
      group_full_name: entry.group_full_name || null,
      name,
      avatar_template: entry.avatar_template || null,
      access_level: accessLevel,
      isReadOnly: accessLevel === "read",
      canReply: accessLevel === "reply",
      isUser: principalType === "user",
      isGroup: principalType === "group",
      label:
        principalType === "group"
          ? entry.group_full_name || groupName
          : name || username,
      subLabel:
        principalType === "group"
          ? groupName
          : name && username
            ? `@${username}`
            : null,
    };
  }

  normalizeSelectedUsernames(values) {
    return (values || [])
      .map((value) => {
        if (typeof value === "string") {
          return value;
        }

        return value?.username || null;
      })
      .filter(Boolean);
  }

  normalizeSelectedGroupNames(values) {
    return (values || [])
      .map((value) => {
        if (typeof value === "string") {
          return value;
        }

        return value?.name || null;
      })
      .filter(Boolean);
  }

  appendUsers(usernames) {
    if (!usernames.length) {
      return;
    }

    const nextEntries = [...this.accessEntries];

    usernames.forEach((username) => {
      if (
        nextEntries.some(
          (entry) => entry.isUser && entry.username?.toLowerCase() === username.toLowerCase(),
        )
      ) {
        return;
      }

      nextEntries.push(
        this.normalizeEntry({
          principal_type: "user",
          username,
          name: username,
          access_level: "reply",
        }),
      );
    });

    this.error = null;
    this.successMessage = null;
    this.accessEntries = nextEntries;
  }

  appendGroups(groupNames) {
    if (!groupNames.length) {
      return;
    }

    const nextEntries = [...this.accessEntries];

    groupNames.forEach((groupName) => {
      const group = this.manageableGroups.find((candidate) => candidate.name === groupName);
      if (!group) {
        return;
      }

      if (nextEntries.some((entry) => entry.isGroup && entry.principal_id === group.id)) {
        return;
      }

      nextEntries.push(
        this.normalizeEntry({
          principal_type: "group",
          principal_id: group.id,
          group_name: group.name,
          group_full_name: group.full_name,
          access_level: "reply",
        }),
      );
    });

    this.error = null;
    this.successMessage = null;
    this.accessEntries = nextEntries;
  }

  @action
  updateSelectedUsernames(values) {
    const usernames = this.normalizeSelectedUsernames(values);

    this.selectedUsernames = usernames;
    this.appendUsers(usernames);
    this.selectedUsernames = [];
  }

  @action
  updateSelectedGroupNames(values) {
    const groupNames = this.normalizeSelectedGroupNames(values);

    this.selectedGroupNames = [];
    this.appendGroups(groupNames);
  }

  @action
  updateEntryAccess(clientKey, event) {
    const accessLevel = event.target.value;

    this.error = null;
    this.successMessage = null;
    this.accessEntries = this.accessEntries.map((entry) =>
      entry.clientKey === clientKey ? this.normalizeEntry({ ...entry, access_level: accessLevel }) : entry,
    );
  }

  @action
  removeEntry(clientKey) {
    this.error = null;
    this.successMessage = null;
    this.accessEntries = this.accessEntries.filter((entry) => entry.clientKey !== clientKey);
  }

  @action
  async setActiveTab(tabName) {
    this.activeTab = tabName;

    if (tabName === "history" && this.canViewHistory && this.historyEvents === null) {
      await this.loadHistory();
    }
  }

  async loadHistory() {
    this.historyLoading = true;
    this.historyError = null;

    try {
      const response = await ajax(`/private-topics/topics/${this.topicId}/access-history`, {
        type: "GET",
      });

      const events = response.private_topic_access_history || [];
      this.historyEvents = events.map((event) => ({
        ...event,
        actionLabel: i18n(`private_topics.allowed_users.history.actions.${event.action}`),
        previousAccessLevelLabel: event.previous_access_level
          ? i18n(`private_topics.allowed_users.access_levels.${event.previous_access_level}`)
          : null,
        newAccessLevelLabel: event.new_access_level
          ? i18n(`private_topics.allowed_users.access_levels.${event.new_access_level}`)
          : null,
      }));
    } catch (error) {
      this.historyError =
        error?.jqXHR?.responseJSON?.errors?.[0] ||
        i18n("private_topics.allowed_users.history.load_error");
    } finally {
      this.historyLoading = false;
    }
  }

  @action
  async saveAllowedUsers() {
    this.saving = true;
    this.error = null;
    this.successMessage = null;

    const users = this.accessEntries
      .filter((entry) => entry.isUser)
      .map((entry) => ({
        id: entry.principal_id,
        username: entry.username,
        access_level: entry.access_level,
      }));
    const groups = this.accessEntries
      .filter((entry) => entry.isGroup)
      .map((entry) => ({
        id: entry.principal_id,
        name: entry.group_name,
        access_level: entry.access_level,
      }));

    try {
      const response = await ajax(`/private-topics/topics/${this.topicId}/allowed-users`, {
        type: "PUT",
        contentType: "application/json",
        data: JSON.stringify({ users, groups }),
      });

      const accessEntries = response.private_topic_access_entries || [];
      const allowedUsers = response.private_topic_allowed_users || [];
      const manageableGroups = response.private_topic_manageable_groups || this.manageableGroups;
      const normalizedEntries = this.normalizeEntries(accessEntries);

      this.accessEntries = normalizedEntries;
      this.post.private_topic_access_entries = accessEntries;
      this.post.private_topic_allowed_users = allowedUsers;
      this.post.private_topic_manageable_groups = manageableGroups;

      if (this.topic) {
        this.topic.private_topic_access_entries = accessEntries;
        this.topic.private_topic_allowed_users = allowedUsers;
        this.topic.private_topic_manageable_groups = manageableGroups;
      }
      this.successMessage = i18n("private_topics.allowed_users.save_success");

      if (this.canViewHistory && this.historyEvents !== null) {
        await this.loadHistory();
      }
    } catch (error) {
      this.error =
        error?.jqXHR?.responseJSON?.errors?.[0] ||
        i18n("private_topics.allowed_users.save_error");
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal @title={{this.title}} @closeModal={{@closeModal}}>
      <:body>
        <p>{{i18n "private_topics.allowed_users.modal_description"}}</p>

        {{#if this.canViewHistory}}
          <div class="private-topic-access-modal__tabs">
            <DButton
              class={{if this.isAccessTabActive "btn-primary" "btn-default"}}
              @action={{fn this.setActiveTab "access"}}
              @label="private_topics.allowed_users.tabs.access"
            />
            <DButton
              class={{if this.isHistoryTabActive "btn-primary" "btn-default"}}
              @action={{fn this.setActiveTab "history"}}
              @label="private_topics.allowed_users.tabs.history"
            />
          </div>
        {{/if}}

        {{#if this.isAccessTabActive}}
          <section class="private-topic-access-modal__section">
            <label class="private-topic-access-modal__label">
              {{i18n "private_topics.allowed_users.user_chooser_label"}}
            </label>
            <UserChooser
              @value={{this.selectedUsernames}}
              @onChange={{this.updateSelectedUsernames}}
              @options={{hash
                excludeCurrentUser=false
                excludedUsernames=this.excludedUsernames
                filterPlaceholder="private_topics.allowed_users.placeholder"
              }}
            />
          </section>

          <section class="private-topic-access-modal__section">
            <label class="private-topic-access-modal__label">
              {{i18n "private_topics.allowed_users.group_chooser_label"}}
            </label>
            <GroupChooser
              @content={{this.availableGroups}}
              @valueProperty={{null}}
              @nameProperty={{null}}
              @value={{this.selectedGroupNames}}
              @onChange={{this.updateSelectedGroupNames}}
            />
          </section>

          <section class="private-topic-access-modal__section">
            <p class="private-topic-access-modal__help">
              {{i18n "private_topics.allowed_users.chooser_help"}}
            </p>

            {{#if this.sortedAccessEntries.length}}
              <table class="private-topic-access-modal__table">
                <thead>
                  <tr>
                    <th>{{i18n "private_topics.allowed_users.table.principal"}}</th>
                    <th>{{i18n "private_topics.allowed_users.table.type"}}</th>
                    <th>{{i18n "private_topics.allowed_users.table.access_level"}}</th>
                    <th>{{i18n "private_topics.allowed_users.table.actions"}}</th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.sortedAccessEntries key="clientKey" as |entry|}}
                    <tr>
                      <td>
                        <strong>{{entry.label}}</strong>
                        {{#if entry.subLabel}}
                          <div>{{entry.subLabel}}</div>
                        {{/if}}
                      </td>
                      <td>
                        {{if entry.isGroup
                          (i18n "private_topics.allowed_users.principal_types.group")
                          (i18n "private_topics.allowed_users.principal_types.user")
                        }}
                      </td>
                      <td>
                        <select
                          {{on "change" (fn this.updateEntryAccess entry.clientKey)}}
                        >
                          <option value="read" selected={{entry.isReadOnly}}>
                            {{i18n "private_topics.allowed_users.access_levels.read"}}
                          </option>
                          <option value="reply" selected={{entry.canReply}}>
                            {{i18n "private_topics.allowed_users.access_levels.reply"}}
                          </option>
                        </select>
                      </td>
                      <td>
                        <DButton
                          class="btn-default"
                          @action={{fn this.removeEntry entry.clientKey}}
                          @label="private_topics.allowed_users.remove"
                        />
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            {{else}}
              <p class="private-topic-allowed-users-modal__empty">
                {{i18n "private_topics.allowed_users.empty"}}
              </p>
            {{/if}}
          </section>
        {{else}}
          <section class="private-topic-access-modal__section">
            {{#if this.historyLoading}}
              <p>{{i18n "private_topics.allowed_users.history.loading"}}</p>
            {{else if this.historyError}}
              <p class="private-topic-allowed-users-modal__error">{{this.historyError}}</p>
            {{else if this.hasHistoryEvents}}
              <ul class="private-topic-access-modal__history">
                {{#each this.historyEvents key="id" as |event|}}
                  <li>
                    <strong>{{event.subject_label}}</strong>
                    <span>{{event.actionLabel}}</span>
                    {{#if event.previousAccessLevelLabel}}
                      <span>
                        {{event.previousAccessLevelLabel}}
                      </span>
                    {{/if}}
                    {{#if event.newAccessLevelLabel}}
                      <span>
                        {{event.newAccessLevelLabel}}
                      </span>
                    {{/if}}
                    <div>
                      {{event.actor_username}}
                      •
                      {{event.created_at_formatted}}
                    </div>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p>{{i18n "private_topics.allowed_users.history.empty"}}</p>
            {{/if}}
          </section>
        {{/if}}

        {{#if this.error}}
          <p class="private-topic-allowed-users-modal__error">
            {{this.error}}
          </p>
        {{/if}}
        {{#if this.successMessage}}
          <p class="private-topic-allowed-users-modal__success">
            {{this.successMessage}}
          </p>
        {{/if}}
      </:body>
      <:footer>
        <DButton
          class="btn-default"
          @action={{@closeModal}}
          @label="private_topics.allowed_users.close"
        />
        <DButton
          class="btn-primary"
          @action={{this.saveAllowedUsers}}
          @disabled={{this.saving}}
          @label={{if this.saving "private_topics.allowed_users.saving" "private_topics.allowed_users.save"}}
        />
      </:footer>
    </DModal>
  </template>
}
