import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import PrivateTopicAllowedUsersModal from "./modal/private-topic-allowed-users-modal";

export default class PrivateTopicManageAccessButton extends Component {
  @service modal;

  static hidden(args) {
    return (
      args.post?.post_number !== 1 ||
      !(args.post?.can_manage_private_topic_access ?? args.post?.can_manage_private_topic_allowed_users)
    );
  }

  @action
  openManageAccessModal() {
    this.modal.show(PrivateTopicAllowedUsersModal, {
      model: {
        post: this.args.post,
      },
    });
  }

  <template>
    <DButton
      ...attributes
      class="post-action-menu__private-topic-manage-access"
      @action={{this.openManageAccessModal}}
      @icon="user-plus"
      @label="private_topics.allowed_users.button"
      @title="private_topics.allowed_users.button"
    />
  </template>
}
