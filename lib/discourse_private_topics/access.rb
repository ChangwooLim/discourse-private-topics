# frozen_string_literal: true

module ::DiscoursePrivateTopics
  READ_ACCESS_LEVEL = "read"
  REPLY_ACCESS_LEVEL = "reply"
  ACCESS_LEVELS = {
    READ_ACCESS_LEVEL => 0,
    REPLY_ACCESS_LEVEL => 1,
  }.freeze
  ACCESS_EVENT_ACTIONS = %w[granted removed access_level_changed].freeze

  class << self
    def private_topics_enabled?
      SiteSetting.private_topics_enabled
    end

    def access_granted_notifications_enabled?
      SiteSetting.private_topics_send_access_granted_notifications
    end

    def allowed_users_storage_ready?
      ::PrivateTopicAllowedUser.table_exists?
    rescue NameError, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def allowed_groups_storage_ready?
      ::PrivateTopicAllowedGroup.table_exists?
    rescue NameError, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def access_events_storage_ready?
      ::PrivateTopicAccessEvent.table_exists?
    rescue NameError, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def access_entries_storage_ready?
      allowed_users_storage_ready? && allowed_groups_storage_ready?
    end

    def access_history_storage_ready?
      access_entries_storage_ready? && access_events_storage_ready?
    end

    def admin_bypass?(user)
      private_topics_enabled? && SiteSetting.private_topics_admin_sees_all && user&.admin?
    end

    def private_category_ids
      CategoryCustomField.where(name: "private_topics_enabled").pluck(:category_id).map(&:to_i)
    end

    def private_category_enabled?(category_id)
      category_id.present? && private_category_ids.include?(category_id.to_i)
    end

    def topic_author_exempt_user_ids(user)
      user_ids = [Discourse.system_user.id]
      user_ids << user.id if user && !user.anonymous?

      group_ids = parse_setting_group_ids(SiteSetting.private_topics_permitted_groups)
      user_ids.concat(GroupUser.where(group_id: group_ids).pluck(:user_id)) if group_ids.any?

      user_ids.uniq
    end

    def allowed_user_manager_group_ids
      parse_setting_group_ids(SiteSetting.private_topics_allowed_user_manager_groups)
    end

    def user_in_allowed_user_manager_group?(user)
      return false unless user&.id

      group_ids = allowed_user_manager_group_ids
      return false if group_ids.empty?

      GroupUser.where(user_id: user.id, group_id: group_ids).exists?
    end

    def filtered_category_ids(user)
      return [] unless private_topics_enabled?

      category_ids = private_category_ids
      return [] if category_ids.empty?
      return [] if user_in_allowed_user_manager_group?(user)

      category_group_map = category_ids.index_with { [] }
      return category_group_map.keys unless user

      excluded_map =
        CategoryCustomField
          .where(category_id: category_ids, name: "private_topics_allowed_groups")
          .each_with_object({}) do |record, result|
            result[record.category_id] = record.value.to_s.split(",").map(&:to_i)
          end

      user_group_ids = user.groups.pluck(:id)
      category_group_map.merge!(excluded_map)
      category_group_map.reject { |_category_id, group_ids| (group_ids & user_group_ids).any? }.keys
    end

    def canonical_access_level(level, default: REPLY_ACCESS_LEVEL)
      normalized_level = level.to_s.presence || default
      return nil if normalized_level.blank?

      ACCESS_LEVELS.key?(normalized_level) ? normalized_level : nil
    end

    def higher_access_level(*levels)
      normalized_levels =
        levels.flatten.compact.map { |level| canonical_access_level(level, default: nil) }.compact
      normalized_levels.max_by { |level| ACCESS_LEVELS[level] }
    end

    def topic_direct_access_level(topic, user)
      return nil unless topic&.id && user&.id
      return nil unless private_category_enabled?(topic.category_id)
      return nil unless allowed_users_storage_ready?

      canonical_access_level(
        PrivateTopicAllowedUser.where(topic_id: topic.id, user_id: user.id).pick(:access_level),
        default: nil,
      )
    end

    def topic_group_access_level(topic, user)
      return nil unless topic&.id && user&.id
      return nil unless private_category_enabled?(topic.category_id)
      return nil unless allowed_groups_storage_ready?

      group_ids = user.groups.pluck(:id)
      return nil if group_ids.empty?

      higher_access_level(
        PrivateTopicAllowedGroup.where(topic_id: topic.id, group_id: group_ids).pluck(:access_level),
      )
    end

    def topic_explicit_access_level(topic, user)
      higher_access_level(topic_direct_access_level(topic, user), topic_group_access_level(topic, user))
    end

    def topic_allowlisted?(topic, user)
      topic_explicit_access_level(topic, user).present?
    end

    def topic_visible_to_user?(topic, user)
      return true unless private_topics_enabled?
      return true if admin_bypass?(user)
      return true unless topic&.category_id

      filtered_ids = filtered_category_ids(user)
      return true unless filtered_ids.include?(topic.category_id)
      return true if topic_author_exempt_user_ids(user).include?(topic.user_id)
      return true if topic_explicit_access_level(topic, user).present?

      false
    end

    def topic_reply_allowed?(topic, user)
      return true unless private_topics_enabled?
      return true if admin_bypass?(user)
      return true unless topic&.category_id

      filtered_ids = filtered_category_ids(user)
      return true unless filtered_ids.include?(topic.category_id)
      return true if topic_author_exempt_user_ids(user).include?(topic.user_id)

      topic_explicit_access_level(topic, user) == REPLY_ACCESS_LEVEL
    end

    def can_manage_topic_access?(topic, user)
      return false unless topic&.id && user&.id
      return false unless private_category_enabled?(topic.category_id)
      return false unless topic_visible_to_user?(topic, user)

      topic.user_id == user.id || user.admin? || user_in_allowed_user_manager_group?(user)
    end

    def can_manage_topic_allowed_users?(topic, user)
      can_manage_topic_access?(topic, user)
    end

    def can_view_topic_access_history?(topic, user)
      topic&.id && user&.admin? && topic_visible_to_user?(topic, user)
    end

    def manageable_groups_for_user(user)
      return [] unless user&.id

      scope = user.admin? ? Group.where.not(id: 0) : user.groups.where.not(id: 0)
      scope = scope.where(automatic: false)

      scope
        .order(:name)
        .pluck(:id, :name, :full_name)
        .map do |id, name, full_name|
          {
            id: id,
            name: name,
            full_name: full_name,
          }
        end
    end

    def filter_visible_topics(relation, user, topics_table: "topics")
      return relation unless private_topics_enabled?
      return relation if admin_bypass?(user)

      private_ids = filtered_category_ids(user)
      return relation if private_ids.empty?

      author_ids = topic_author_exempt_user_ids(user)
      conditions = [
        "#{topics_table}.category_id NOT IN (:private_category_ids)",
        "#{topics_table}.user_id IN (:author_ids)",
      ]
      values = { private_category_ids: private_ids, author_ids: author_ids }

      if user&.id && allowed_users_storage_ready?
        conditions << <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM private_topic_allowed_users
            WHERE private_topic_allowed_users.topic_id = #{topics_table}.id
              AND private_topic_allowed_users.user_id = :viewer_id
          )
        SQL
        values[:viewer_id] = user.id
      end

      if user&.id && allowed_groups_storage_ready?
        conditions << <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM private_topic_allowed_groups
            INNER JOIN group_users
              ON group_users.group_id = private_topic_allowed_groups.group_id
            WHERE private_topic_allowed_groups.topic_id = #{topics_table}.id
              AND group_users.user_id = :viewer_id
          )
        SQL
        values[:viewer_id] = user.id
      end

      relation.where("(#{conditions.join(' OR ')})", values)
    end

    def parse_usernames(raw_usernames)
      values =
        case raw_usernames
        when String
          raw_usernames.split(",")
        when Array
          raw_usernames
        else
          []
        end

      values.map { |value| value.to_s.strip.downcase }.reject(&:blank?).uniq
    end

    def parse_integer_ids(raw_ids)
      values =
        case raw_ids
        when String
          raw_ids.split(",")
        when Array
          raw_ids
        else
          []
        end

      values.map { |value| Integer(value, exception: false) }.compact.uniq
    end

    def access_entries_from_raw!(topic:, actor:, users: nil, groups: nil, user_ids: nil, usernames: nil)
      ensure_access_entries_storage_ready!

      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.private_category_required") unless private_category_enabled?(topic.category_id)

      {
        users: user_entries_from_raw!(topic: topic, users: users, user_ids: user_ids, usernames: usernames),
        groups: group_entries_from_raw!(groups: groups, actor: actor),
      }
    end

    def replace_topic_access!(topic:, actor:, user_entries:, group_entries:)
      ensure_access_entries_storage_ready!

      previous_state = current_access_state(topic)
      next_state = normalize_access_state(user_entries: user_entries, group_entries: group_entries)
      diff = build_access_diff(previous_state: previous_state, next_state: next_state)

      PrivateTopicAllowedUser.transaction do
        sync_user_entries!(topic: topic, actor: actor, user_entries: user_entries)
        sync_group_entries!(topic: topic, actor: actor, group_entries: group_entries)
        log_access_events!(topic: topic, actor: actor, diff: diff) if access_events_storage_ready?
      end

      notify_new_user_grants(topic: topic, actor: actor, diff: diff)

      diff
    end

    def serialized_allowed_users(topic)
      return [] unless topic&.id
      return [] unless allowed_users_storage_ready?

      PrivateTopicAllowedUser
        .includes(:user)
        .where(topic_id: topic.id)
        .order(:created_at)
        .map do |record|
          {
            id: record.user.id,
            username: record.user.username,
            name: record.user.name,
            avatar_template: record.user.avatar_template,
            access_level: canonical_access_level(record.access_level, default: nil),
          }
        end
    end

    def serialized_access_entries(topic)
      return [] unless topic&.id
      return [] unless access_entries_storage_ready?

      user_entries =
        PrivateTopicAllowedUser
          .includes(:user)
          .where(topic_id: topic.id)
          .order(:created_at)
          .map do |record|
            {
              principal_type: "user",
              principal_id: record.user.id,
              id: record.user.id,
              username: record.user.username,
              name: record.user.name,
              avatar_template: record.user.avatar_template,
              access_level: canonical_access_level(record.access_level, default: nil),
            }
          end

      group_entries =
        PrivateTopicAllowedGroup
          .includes(:group)
          .where(topic_id: topic.id)
          .order(:created_at)
          .map do |record|
            {
              principal_type: "group",
              principal_id: record.group.id,
              id: record.group.id,
              group_name: record.group.name,
              group_full_name: record.group.full_name,
              access_level: canonical_access_level(record.access_level, default: nil),
            }
          end

      user_entries + group_entries
    end

    def serialized_access_history(topic)
      return [] unless topic&.id
      return [] unless access_history_storage_ready?

      PrivateTopicAccessEvent
        .includes(:actor)
        .where(topic_id: topic.id)
        .order(created_at: :desc)
        .map do |record|
          {
            id: record.id,
            action: record.action,
            subject_type: record.subject_type,
            subject_id: record.subject_id,
            subject_label: record.metadata["subject_label"],
            previous_access_level: canonical_access_level(record.previous_access_level, default: nil),
            new_access_level: canonical_access_level(record.new_access_level, default: nil),
            actor_id: record.actor_id,
            actor_username: record.actor&.username || record.metadata["actor_username"],
            created_at: record.created_at&.iso8601,
            created_at_formatted: record.created_at&.strftime("%Y-%m-%d %H:%M:%S"),
          }
        end
    end

    private

    def parse_setting_group_ids(raw_ids)
      raw_ids.to_s.split("|").map(&:to_i).reject(&:zero?).uniq
    end

    def user_entries_from_raw!(topic:, users:, user_ids:, usernames:)
      if users.present?
        parse_user_entries_payload!(topic: topic, raw_entries: users)
      elsif user_ids.present? || usernames.present?
        parse_legacy_user_entries!(topic: topic, user_ids: user_ids, usernames: usernames)
      else
        []
      end
    end

    def parse_user_entries_payload!(topic:, raw_entries:)
      entry_map = {}
      missing_user_ids = []
      missing_usernames = []

      Array(raw_entries).each do |raw_entry|
        entry = normalize_payload_entry(raw_entry)
        access_level = canonical_access_level(entry["access_level"])
        raise_invalid_access_level! unless access_level

        user =
          if entry["id"].present?
            User.find_by(id: Integer(entry["id"], exception: false))
          elsif entry["username"].present?
            User.find_by(username_lower: entry["username"].to_s.strip.downcase)
          end

        if user.blank?
          if entry["id"].present?
            missing_user_ids << entry["id"].to_s
          elsif entry["username"].present?
            missing_usernames << entry["username"].to_s
          end
          next
        end

        entry_map[user.id] = {
          user: user,
          access_level: higher_access_level(entry_map.dig(user.id, :access_level), access_level),
        }
      end

      raise_invalid_user_ids!(missing_user_ids) if missing_user_ids.any?
      raise_invalid_users!(missing_usernames) if missing_usernames.any?

      validate_user_entries!(topic: topic, user_entries: entry_map.values)
    end

    def parse_legacy_user_entries!(topic:, user_ids:, usernames:)
      users =
        if user_ids.present?
          allowed_users_from_ids!(raw_user_ids: user_ids)
        else
          allowed_users_from_usernames!(raw_usernames: usernames)
        end

      validate_user_entries!(
        topic: topic,
        user_entries: users.map { |user| { user: user, access_level: REPLY_ACCESS_LEVEL } },
      )
    end

    def group_entries_from_raw!(groups:, actor:)
      return [] if groups.blank?

      entry_map = {}
      missing_group_ids = []
      missing_group_names = []

      Array(groups).each do |raw_entry|
        entry = normalize_payload_entry(raw_entry)
        access_level = canonical_access_level(entry["access_level"])
        raise_invalid_access_level! unless access_level

        group =
          if entry["id"].present?
            Group.find_by(id: Integer(entry["id"], exception: false))
          elsif entry["name"].present?
            Group.find_by("LOWER(name) = ?", entry["name"].to_s.strip.downcase)
          end

        if group.blank?
          if entry["id"].present?
            missing_group_ids << entry["id"].to_s
          elsif entry["name"].present?
            missing_group_names << entry["name"].to_s
          end
          next
        end

        if group.id.to_i.zero?
          missing_group_names << group.name
          next
        end

        entry_map[group.id] = {
          group: group,
          access_level: higher_access_level(entry_map.dig(group.id, :access_level), access_level),
        }
      end

      raise_invalid_group_ids!(missing_group_ids) if missing_group_ids.any?
      raise_invalid_groups!(missing_group_names) if missing_group_names.any?

      validate_group_entries!(actor: actor, group_entries: entry_map.values)
    end

    def validate_group_entries!(actor:, group_entries:)
      return group_entries if actor&.admin?

      manageable_group_ids = manageable_groups_for_user(actor).map { |group| group[:id] }
      unauthorized_groups =
        group_entries.map { |entry| entry[:group] }.reject { |group| manageable_group_ids.include?(group.id) }

      if unauthorized_groups.any?
        raise Discourse::InvalidParameters,
              I18n.t(
                "private_topics.errors.unauthorized_groups",
                group_names: unauthorized_groups.map(&:name).join(", "),
              )
      end

      group_entries
    end

    def allowed_users_from_ids!(raw_user_ids:)
      normalized_user_ids = parse_integer_ids(raw_user_ids)
      return [] if normalized_user_ids.empty?

      users = User.where(id: normalized_user_ids).to_a
      found_user_ids = users.map(&:id)
      missing_user_ids = normalized_user_ids - found_user_ids
      raise_invalid_user_ids!(missing_user_ids) if missing_user_ids.any?

      users
    end

    def allowed_users_from_usernames!(raw_usernames:)
      normalized_usernames = parse_usernames(raw_usernames)
      return [] if normalized_usernames.empty?

      users = User.where(username_lower: normalized_usernames).to_a
      found_usernames = users.map(&:username_lower)
      missing_usernames = normalized_usernames - found_usernames
      raise_invalid_users!(missing_usernames) if missing_usernames.any?

      users
    end

    def validate_user_entries!(topic:, user_entries:)
      inaccessible_users = user_entries.map { |entry| entry[:user] }.reject { |user| Guardian.new(user).can_see?(topic.category) }

      if inaccessible_users.any?
        raise Discourse::InvalidParameters,
              I18n.t(
                "private_topics.errors.users_without_category_access",
                usernames: inaccessible_users.map(&:username).join(", "),
              )
      end

      user_entries.reject { |entry| entry[:user].id == topic.user_id }
    end

    def normalize_payload_entry(entry)
      if entry.respond_to?(:to_unsafe_h)
        entry.to_unsafe_h
      elsif entry.respond_to?(:to_h)
        entry.to_h
      else
        {}
      end.stringify_keys
    end

    def current_access_state(topic)
      {
        users:
          if allowed_users_storage_ready?
            PrivateTopicAllowedUser.where(topic_id: topic.id).pluck(:user_id, :access_level).to_h.transform_values { |level| canonical_access_level(level, default: nil) }
          else
            {}
          end,
        groups:
          if allowed_groups_storage_ready?
            PrivateTopicAllowedGroup.where(topic_id: topic.id).pluck(:group_id, :access_level).to_h.transform_values { |level| canonical_access_level(level, default: nil) }
          else
            {}
          end,
      }
    end

    def normalize_access_state(user_entries:, group_entries:)
      {
        users: user_entries.to_h { |entry| [entry[:user].id, canonical_access_level(entry[:access_level], default: nil)] },
        groups: group_entries.to_h { |entry| [entry[:group].id, canonical_access_level(entry[:access_level], default: nil)] },
      }
    end

    def build_access_diff(previous_state:, next_state:)
      diff = []

      %i[users groups].each do |principal_kind|
        previous_entries = previous_state[principal_kind]
        next_entries = next_state[principal_kind]
        subject_type = principal_kind == :users ? "user" : "group"

        (next_entries.keys - previous_entries.keys).each do |principal_id|
          diff << {
            subject_type: subject_type,
            subject_id: principal_id,
            action: "granted",
            previous_access_level: nil,
            new_access_level: next_entries[principal_id],
          }
        end

        (previous_entries.keys - next_entries.keys).each do |principal_id|
          diff << {
            subject_type: subject_type,
            subject_id: principal_id,
            action: "removed",
            previous_access_level: previous_entries[principal_id],
            new_access_level: nil,
          }
        end

        (previous_entries.keys & next_entries.keys).each do |principal_id|
          next if previous_entries[principal_id] == next_entries[principal_id]

          diff << {
            subject_type: subject_type,
            subject_id: principal_id,
            action: "access_level_changed",
            previous_access_level: previous_entries[principal_id],
            new_access_level: next_entries[principal_id],
          }
        end
      end

      diff
    end

    def sync_user_entries!(topic:, actor:, user_entries:)
      if user_entries.empty?
        PrivateTopicAllowedUser.where(topic_id: topic.id).delete_all
        return
      end

      user_map = user_entries.to_h { |entry| [entry[:user].id, entry[:access_level]] }

      PrivateTopicAllowedUser.where(topic_id: topic.id).where.not(user_id: user_map.keys).delete_all

      existing_records = PrivateTopicAllowedUser.where(topic_id: topic.id, user_id: user_map.keys).index_by(&:user_id)

      user_map.each do |user_id, access_level|
        if (record = existing_records[user_id])
          record.update!(access_level: access_level, granted_by_id: actor.id)
        else
          PrivateTopicAllowedUser.create!(
            topic_id: topic.id,
            user_id: user_id,
            granted_by_id: actor.id,
            access_level: access_level,
          )
        end
      end
    end

    def sync_group_entries!(topic:, actor:, group_entries:)
      if group_entries.empty?
        PrivateTopicAllowedGroup.where(topic_id: topic.id).delete_all
        return
      end

      group_map = group_entries.to_h { |entry| [entry[:group].id, entry[:access_level]] }

      PrivateTopicAllowedGroup.where(topic_id: topic.id).where.not(group_id: group_map.keys).delete_all

      existing_records = PrivateTopicAllowedGroup.where(topic_id: topic.id, group_id: group_map.keys).index_by(&:group_id)

      group_map.each do |group_id, access_level|
        if (record = existing_records[group_id])
          record.update!(access_level: access_level, granted_by_id: actor.id)
        else
          PrivateTopicAllowedGroup.create!(
            topic_id: topic.id,
            group_id: group_id,
            granted_by_id: actor.id,
            access_level: access_level,
          )
        end
      end
    end

    def log_access_events!(topic:, actor:, diff:)
      return if diff.empty?

      user_labels = User.where(id: diff.select { |change| change[:subject_type] == "user" }.map { |change| change[:subject_id] }).pluck(:id, :username).to_h
      group_labels = Group.where(id: diff.select { |change| change[:subject_type] == "group" }.map { |change| change[:subject_id] }).pluck(:id, :name).to_h

      diff.each do |change|
        label =
          if change[:subject_type] == "user"
            user_labels[change[:subject_id]]
          else
            group_labels[change[:subject_id]]
          end

        PrivateTopicAccessEvent.create!(
          topic_id: topic.id,
          actor_id: actor.id,
          subject_type: change[:subject_type],
          subject_id: change[:subject_id],
          action: change[:action],
          previous_access_level: change[:previous_access_level],
          new_access_level: change[:new_access_level],
          metadata: {
            subject_label: label,
            actor_username: actor.username,
          },
        )
      end
    end

    def notify_new_user_grants(topic:, actor:, diff:)
      return unless access_granted_notifications_enabled?

      added_user_ids =
        diff
          .select { |change| change[:subject_type] == "user" && change[:action] == "granted" }
          .map { |change| [change[:subject_id], change[:new_access_level]] }

      added_user_ids.each do |user_id, access_level|
        recipient = User.find_by(id: user_id)
        next if recipient.blank?
        next if recipient.id == actor.id

        locale = recipient.effective_locale.presence || I18n.default_locale
        access_level_label =
          I18n.with_locale(locale) do
            I18n.t("private_topics.access_levels.#{canonical_access_level(access_level)}")
          end
        title =
          I18n.with_locale(locale) do
            I18n.t("private_topics.notifications.access_granted.subject", topic_title: topic.title)
          end
        raw =
          I18n.with_locale(locale) do
            I18n.t(
              "private_topics.notifications.access_granted.body",
              actor_username: actor.username,
              access_level: access_level_label,
              topic_title: topic.title,
              topic_url: topic.relative_url,
            )
          end

        PostCreator.create!(
          Discourse.system_user,
          title: title,
          raw: raw,
          archetype: Archetype.private_message,
          target_usernames: recipient.username,
        )
      rescue StandardError => error
        Rails.logger.warn(
          "[#{DiscoursePrivateTopics::PLUGIN_NAME}] Failed to deliver access-granted DM " \
            "for topic #{topic.id} to user #{user_id}: #{error.class}: #{error.message}",
        )
      end
    end

    def raise_invalid_access_level!
      raise Discourse::InvalidParameters, I18n.t("private_topics.errors.invalid_access_level")
    end

    def raise_invalid_user_ids!(user_ids)
      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.invalid_user_ids", user_ids: Array(user_ids).join(", "))
    end

    def raise_invalid_users!(usernames)
      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.invalid_users", usernames: Array(usernames).join(", "))
    end

    def raise_invalid_group_ids!(group_ids)
      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.invalid_group_ids", group_ids: Array(group_ids).join(", "))
    end

    def raise_invalid_groups!(group_names)
      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.invalid_groups", group_names: Array(group_names).join(", "))
    end

    def ensure_access_entries_storage_ready!
      return if access_entries_storage_ready?

      raise Discourse::InvalidParameters,
            I18n.t("private_topics.errors.allowed_users_storage_unavailable")
    end
  end
end
