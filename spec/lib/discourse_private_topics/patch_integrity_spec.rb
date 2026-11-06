# frozen_string_literal: true

require "rails_helper"

# Every patch wraps a core method with prepend and calls super. When a Discourse upgrade renames
# such a method or changes its arguments, the patch stops running or super raises, and private
# topics can show up again without any behaviour spec failing. These checks fail first and name the
# method, so run them on every Discourse upgrade.
describe DiscoursePrivateTopics do
  patches = {
    "TopicGuardian#can_see_topic?" => [
      -> { Guardian },
      -> { DiscoursePrivateTopics::Patches::TopicGuardian },
      :can_see_topic?,
    ],
    "Guardian#can_create_post_on_topic?" => [
      -> { Guardian },
      -> { DiscoursePrivateTopics::Patches::Guardian },
      :can_create_post_on_topic?,
    ],
    "Search#execute" => [
      -> { Search },
      -> { DiscoursePrivateTopics::Patches::Search },
      :execute,
    ],
    "Topic.recent" => [
      -> { Topic.singleton_class },
      -> { DiscoursePrivateTopics::Patches::Topic },
      :recent,
    ],
    "Topic.for_digest" => [
      -> { Topic.singleton_class },
      -> { DiscoursePrivateTopics::Patches::Topic },
      :for_digest,
    ],
    "Topic.similar_to" => [
      -> { Topic.singleton_class },
      -> { DiscoursePrivateTopics::Patches::Topic },
      :similar_to,
    ],
    "UserAction.apply_common_filters" => [
      -> { UserAction.singleton_class },
      -> { DiscoursePrivateTopics::Patches::UserAction },
      :apply_common_filters,
    ],
    "UserSummary#topics" => [
      -> { UserSummary },
      -> { DiscoursePrivateTopics::Patches::UserSummary },
      :topics,
    ],
    "UserSummary#replies" => [
      -> { UserSummary },
      -> { DiscoursePrivateTopics::Patches::UserSummary },
      :replies,
    ],
    "UserSummary#links" => [
      -> { UserSummary },
      -> { DiscoursePrivateTopics::Patches::UserSummary },
      :links,
    ],
    "CategoryDetailedSerializer#include_displayable_topics?" => [
      -> { CategoryDetailedSerializer },
      -> { DiscoursePrivateTopics::Patches::CategoryDetailedSerializer },
      :include_displayable_topics?,
    ],
  }

  optional_patches = {
    "DiscourseSolved::SolvedTopicsController#by_user" => [
      "DiscourseSolved::SolvedTopicsController",
      -> { DiscoursePrivateTopics::Patches::DiscourseSolvedSolvedTopicsController },
      :by_user,
    ],
    "DiscourseAi::Embeddings::SemanticSearch#search_for_topics" => [
      "DiscourseAi::Embeddings::SemanticSearch",
      -> { DiscoursePrivateTopics::Patches::DiscourseAiEmbeddingsSemanticSearch },
      :search_for_topics,
    ],
    "Follow::NotificationHandler#handle" => [
      "Follow::NotificationHandler",
      -> { DiscoursePrivateTopics::Patches::FollowNotificationHandler },
      :handle,
    ],
  }

  def defines?(mod, name)
    mod.instance_methods(false).include?(name) || mod.private_instance_methods(false).include?(name)
  end

  # The first definition below the patch is what its super calls: core, or another plugin's wrapper.
  def wrapped_method(target, patch, name)
    ancestors = target.ancestors
    below = ancestors.drop(ancestors.index(patch) + 1)
    owner = below.find { |mod| defines?(mod, name) }
    owner&.instance_method(name)
  end

  def call_shape(method)
    method.parameters.map { |kind, arg| %i[key keyreq].include?(kind) ? [kind, arg] : kind }
  end

  def passes_everything_through?(method)
    method.parameters.all? { |kind, _| %i[rest keyrest block].include?(kind) }
  end

  def expect_patch_wraps(label, target, patch, name)
    expect(target.ancestors).to include(patch), "#{label}: #{patch} is not prepended to #{target}"

    original = wrapped_method(target, patch, name)
    expect(original).to be_present, "#{label} no longer exists below the patch"

    ours = patch.instance_method(name)
    if !passes_everything_through?(ours)
      expect(call_shape(ours)).to eq(call_shape(original)),
      "#{label} now takes #{original.parameters.inspect}, the patch takes #{ours.parameters.inspect}"
    end
  end

  patches.each do |label, (target, patch, name)|
    it("wraps #{label}") { expect_patch_wraps(label, target.call, patch.call, name) }
  end

  optional_patches.each do |label, (target_name, patch, name)|
    it "wraps #{label} when that code is loaded" do
      target = target_name.safe_constantize
      skip "#{target_name} is not loaded" if target.nil?
      expect_patch_wraps(label, target, patch.call, name)
    end
  end

  it "registers the topic list filter" do
    expect(TopicQuery.instance_variable_get(:@custom_filters)).to have_key(:private_topics)
  end
end
