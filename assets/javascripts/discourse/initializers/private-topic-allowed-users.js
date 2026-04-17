import { apiInitializer } from "discourse/lib/api";
import PrivateTopicManageAccessButton from "../components/private-topic-manage-access-button";

export default apiInitializer((api) => {
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { post, firstButtonKey } }) => {
      const canManageAccess =
        post?.can_manage_private_topic_access ?? post?.can_manage_private_topic_allowed_users;

      if (post?.post_number !== 1 || !canManageAccess) {
        return;
      }

      if (firstButtonKey) {
        dag.add("private-topic-manage-access", PrivateTopicManageAccessButton, {
          after: firstButtonKey,
        });
      } else {
        dag.add("private-topic-manage-access", PrivateTopicManageAccessButton);
      }
    },
  );
});
