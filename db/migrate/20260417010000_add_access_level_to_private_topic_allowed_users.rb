# frozen_string_literal: true

class AddAccessLevelToPrivateTopicAllowedUsers < ActiveRecord::Migration[7.1]
  def up
    unless column_exists?(:private_topic_allowed_users, :access_level)
      add_column :private_topic_allowed_users, :access_level, :string, null: false, default: "reply"
    end

    execute <<~SQL
      UPDATE private_topic_allowed_users
      SET access_level = 'reply'
      WHERE access_level IS NULL OR access_level = ''
    SQL
  end

  def down
    remove_column :private_topic_allowed_users, :access_level if column_exists?(:private_topic_allowed_users, :access_level)
  end
end
