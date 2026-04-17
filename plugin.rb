# name: discourse-private-topics
# about: Allows to keep topics private to the topic creator and specific groups.
# version: 1.7.0
# authors: Communiteq
# meta_topic_id: 268646
# url: https://github.com/communiteq/discourse-private-topics

enabled_site_setting :private_topics_enabled

require_relative "lib/discourse_private_topics"
require_relative "lib/discourse_private_topics/access"
require_relative "app/models/private_topic_allowed_user"
require_relative "app/models/private_topic_allowed_group"
require_relative "app/models/private_topic_access_event"
require_relative "lib/discourse_private_topics/modifiers/topic_view_link_counts"
require_relative "lib/discourse_private_topics/patches/category_detailed_serializer"
require_relative "lib/discourse_private_topics/patches/discourse_ai_embeddings_semantic_search"
require_relative "lib/discourse_private_topics/patches/discourse_solved_solved_topics_controller"
require_relative "lib/discourse_private_topics/patches/follow_notification_handler"
require_relative "lib/discourse_private_topics/patches/guardian"
require_relative "lib/discourse_private_topics/patches/post"
require_relative "lib/discourse_private_topics/patches/search"
require_relative "lib/discourse_private_topics/patches/topic"
require_relative "lib/discourse_private_topics/patches/topic_guardian"
require_relative "lib/discourse_private_topics/patches/topic_query"
require_relative "lib/discourse_private_topics/patches/user_action"
require_relative "lib/discourse_private_topics/patches/user_summary"

after_initialize do
  load File.expand_path("app/controllers/discourse_private_topics/allowed_users_controller.rb", __dir__)
  load File.expand_path("config/routes.rb", __dir__)

  Site.preloaded_category_custom_fields << "private_topics_enabled"
  Site.preloaded_category_custom_fields << "private_topics_allowed_groups"

  class ::Post
    prepend DiscoursePrivateTopics::Patches::Post
  end

  class ::Search
    prepend DiscoursePrivateTopics::Patches::Search
  end

  module ::TopicGuardian
    prepend DiscoursePrivateTopics::Patches::TopicGuardian
  end

  class ::Guardian
    prepend DiscoursePrivateTopics::Patches::Guardian
  end

  class ::UserAction
    singleton_class.prepend DiscoursePrivateTopics::Patches::UserAction
  end

  class ::UserSummary
    prepend DiscoursePrivateTopics::Patches::UserSummary
  end

  class ::CategoryDetailedSerializer
    prepend DiscoursePrivateTopics::Patches::CategoryDetailedSerializer
  end

  class << ::Topic
    prepend DiscoursePrivateTopics::Patches::Topic
  end

  if defined?(Follow::NotificationHandler)
    class ::Follow::NotificationHandler
      prepend DiscoursePrivateTopics::Patches::FollowNotificationHandler
    end
  end

  if defined?(DiscourseAi::Embeddings::SemanticSearch)
    class ::DiscourseAi::Embeddings::SemanticSearch
      prepend DiscoursePrivateTopics::Patches::DiscourseAiEmbeddingsSemanticSearch
    end
  end

  if defined?(DiscourseSolved::SolvedTopicsController)
    class ::DiscourseSolved::SolvedTopicsController
      prepend DiscoursePrivateTopics::Patches::DiscourseSolvedSolvedTopicsController
    end
  end

  TopicQuery.add_custom_filter(:private_topics) do |result, query|
    DiscoursePrivateTopics::Patches::TopicQuery.filter(result, query)
  end

  register_modifier(:topic_view_link_counts) do |link_counts|
    DiscoursePrivateTopics::Modifiers::TopicViewLinkCounts.call(link_counts)
  end

  add_to_serializer(:topic_view, :can_manage_private_topic_access) do
    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :can_manage_private_topic_allowed_users) do
    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :can_view_private_topic_access_history) do
    topic = object.topic

    DiscoursePrivateTopics.access_history_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_view_topic_access_history?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :include_private_topic_access_entries?) do
    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :private_topic_access_entries) do
    DiscoursePrivateTopics.serialized_access_entries(object.topic)
  end

  add_to_serializer(:topic_view, :include_private_topic_manageable_groups?) do
    topic = object.topic

    scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :private_topic_manageable_groups) do
    DiscoursePrivateTopics.manageable_groups_for_user(scope.user)
  end

  add_to_serializer(:topic_view, :include_private_topic_allowed_users?) do
    topic = object.topic

    DiscoursePrivateTopics.allowed_users_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:topic_view, :private_topic_allowed_users) do
    DiscoursePrivateTopics.serialized_allowed_users(object.topic)
  end

  add_to_serializer(:post, :can_manage_private_topic_access) do
    next false unless object.post_number == 1

    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:post, :can_manage_private_topic_allowed_users) do
    next false unless object.post_number == 1

    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:post, :can_view_private_topic_access_history) do
    next false unless object.post_number == 1

    topic = object.topic

    DiscoursePrivateTopics.access_history_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_view_topic_access_history?(topic, scope.user)
  end

  add_to_serializer(:post, :include_private_topic_access_entries?) do
    next false unless object.post_number == 1

    topic = object.topic

    DiscoursePrivateTopics.access_entries_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:post, :private_topic_access_entries) do
    next [] unless object.post_number == 1

    DiscoursePrivateTopics.serialized_access_entries(object.topic)
  end

  add_to_serializer(:post, :include_private_topic_manageable_groups?) do
    next false unless object.post_number == 1

    topic = object.topic

    scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:post, :private_topic_manageable_groups) do
    next [] unless object.post_number == 1

    DiscoursePrivateTopics.manageable_groups_for_user(scope.user)
  end

  add_to_serializer(:post, :include_private_topic_allowed_users?) do
    next false unless object.post_number == 1

    topic = object.topic

    DiscoursePrivateTopics.allowed_users_storage_ready? &&
      scope.can_see_topic?(topic) &&
      DiscoursePrivateTopics.can_manage_topic_access?(topic, scope.user)
  end

  add_to_serializer(:post, :private_topic_allowed_users) do
    next [] unless object.post_number == 1

    DiscoursePrivateTopics.serialized_allowed_users(object.topic)
  end
end
