# frozen_string_literal: true

class CreatePrivateTopicAllowedGroups < ActiveRecord::Migration[7.1]
  def up
    unless table_exists?(:private_topic_allowed_groups)
      create_table :private_topic_allowed_groups do |t|
        t.integer :topic_id, null: false
        t.integer :group_id, null: false
        t.integer :granted_by_id, null: false
        t.string :access_level, null: false, default: "reply"
        t.timestamps
      end
    end

    add_index :private_topic_allowed_groups, %i[topic_id group_id], unique: true unless index_exists?(:private_topic_allowed_groups, %i[topic_id group_id], unique: true)
    add_index :private_topic_allowed_groups, :topic_id unless index_exists?(:private_topic_allowed_groups, :topic_id)
    add_index :private_topic_allowed_groups, :group_id unless index_exists?(:private_topic_allowed_groups, :group_id)
    add_index :private_topic_allowed_groups, :granted_by_id unless index_exists?(:private_topic_allowed_groups, :granted_by_id)

    unless foreign_key_exists?(:private_topic_allowed_groups, :topics, column: :topic_id)
      add_foreign_key :private_topic_allowed_groups, :topics, column: :topic_id, on_delete: :cascade
    end

    unless foreign_key_exists?(:private_topic_allowed_groups, :groups, column: :group_id)
      add_foreign_key :private_topic_allowed_groups, :groups, column: :group_id, on_delete: :cascade
    end

    unless foreign_key_exists?(:private_topic_allowed_groups, :users, column: :granted_by_id)
      add_foreign_key :private_topic_allowed_groups, :users, column: :granted_by_id
    end
  end

  def down
    remove_foreign_key :private_topic_allowed_groups, column: :granted_by_id if foreign_key_exists?(:private_topic_allowed_groups, :users, column: :granted_by_id)
    remove_foreign_key :private_topic_allowed_groups, column: :group_id if foreign_key_exists?(:private_topic_allowed_groups, :groups, column: :group_id)
    remove_foreign_key :private_topic_allowed_groups, column: :topic_id if foreign_key_exists?(:private_topic_allowed_groups, :topics, column: :topic_id)

    remove_index :private_topic_allowed_groups, column: %i[topic_id group_id] if index_exists?(:private_topic_allowed_groups, %i[topic_id group_id])
    remove_index :private_topic_allowed_groups, :topic_id if index_exists?(:private_topic_allowed_groups, :topic_id)
    remove_index :private_topic_allowed_groups, :group_id if index_exists?(:private_topic_allowed_groups, :group_id)
    remove_index :private_topic_allowed_groups, :granted_by_id if index_exists?(:private_topic_allowed_groups, :granted_by_id)

    drop_table :private_topic_allowed_groups if table_exists?(:private_topic_allowed_groups)
  end
end
