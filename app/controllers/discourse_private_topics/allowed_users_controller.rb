# frozen_string_literal: true

module DiscoursePrivateTopics
  class AllowedUsersController < ::ApplicationController
    requires_login

    def history
      topic = Topic.find(params.require(:topic_id))

      guardian.ensure_can_see!(topic)
      raise Discourse::InvalidAccess unless DiscoursePrivateTopics.can_view_topic_access_history?(topic, current_user)

      render json: success_json.merge(private_topic_access_history: DiscoursePrivateTopics.serialized_access_history(topic))
    end

    def update
      topic = Topic.find(params.require(:topic_id))

      guardian.ensure_can_see!(topic)
      raise Discourse::InvalidAccess unless DiscoursePrivateTopics.can_manage_topic_access?(topic, current_user)

      access_entries =
        DiscoursePrivateTopics.access_entries_from_raw!(
          topic: topic,
          actor: current_user,
          users: params[:users],
          groups: params[:groups],
          user_ids: params[:user_ids],
          usernames: params[:usernames],
        )

      DiscoursePrivateTopics.replace_topic_access!(
        topic: topic,
        actor: current_user,
        user_entries: access_entries[:users],
        group_entries: access_entries[:groups],
      )

      render json:
               success_json.merge(
                 private_topic_access_entries: DiscoursePrivateTopics.serialized_access_entries(topic),
                 private_topic_allowed_users: DiscoursePrivateTopics.serialized_allowed_users(topic),
                 private_topic_manageable_groups: DiscoursePrivateTopics.manageable_groups_for_user(current_user),
                 can_view_private_topic_access_history:
                   DiscoursePrivateTopics.can_view_topic_access_history?(topic, current_user),
               )
    end
  end
end
