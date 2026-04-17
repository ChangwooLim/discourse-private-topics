# frozen_string_literal: true

class CreatePrivateTopicAllowedUsers < ActiveRecord::Migration[7.1]
  def up
    unless table_exists?(:private_topic_allowed_users)
      create_table :private_topic_allowed_users do |t|
        t.integer :topic_id, null: false
        t.integer :user_id, null: false
        t.integer :granted_by_id, null: false
        t.timestamps
      end
    end

    add_index :private_topic_allowed_users, %i[topic_id user_id], unique: true unless index_exists?(:private_topic_allowed_users, %i[topic_id user_id], unique: true)
    add_index :private_topic_allowed_users, :topic_id unless index_exists?(:private_topic_allowed_users, :topic_id)
    add_index :private_topic_allowed_users, :user_id unless index_exists?(:private_topic_allowed_users, :user_id)
    add_index :private_topic_allowed_users, :granted_by_id unless index_exists?(:private_topic_allowed_users, :granted_by_id)

    unless foreign_key_exists?(:private_topic_allowed_users, :topics, column: :topic_id)
      add_foreign_key :private_topic_allowed_users, :topics, column: :topic_id, on_delete: :cascade
    end

    unless foreign_key_exists?(:private_topic_allowed_users, :users, column: :user_id)
      add_foreign_key :private_topic_allowed_users, :users, column: :user_id, on_delete: :cascade
    end

    unless foreign_key_exists?(:private_topic_allowed_users, :users, column: :granted_by_id)
      add_foreign_key :private_topic_allowed_users, :users, column: :granted_by_id
    end
  end

  def down
    remove_foreign_key :private_topic_allowed_users, column: :granted_by_id if foreign_key_exists?(:private_topic_allowed_users, :users, column: :granted_by_id)
    remove_foreign_key :private_topic_allowed_users, column: :user_id if foreign_key_exists?(:private_topic_allowed_users, :users, column: :user_id)
    remove_foreign_key :private_topic_allowed_users, column: :topic_id if foreign_key_exists?(:private_topic_allowed_users, :topics, column: :topic_id)

    remove_index :private_topic_allowed_users, column: %i[topic_id user_id] if index_exists?(:private_topic_allowed_users, %i[topic_id user_id])
    remove_index :private_topic_allowed_users, :topic_id if index_exists?(:private_topic_allowed_users, :topic_id)
    remove_index :private_topic_allowed_users, :user_id if index_exists?(:private_topic_allowed_users, :user_id)
    remove_index :private_topic_allowed_users, :granted_by_id if index_exists?(:private_topic_allowed_users, :granted_by_id)

    drop_table :private_topic_allowed_users if table_exists?(:private_topic_allowed_users)
  end
end
