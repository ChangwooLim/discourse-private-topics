# frozen_string_literal: true

class CreatePrivateTopicAccessEvents < ActiveRecord::Migration[7.1]
  def up
    unless table_exists?(:private_topic_access_events)
      create_table :private_topic_access_events do |t|
        t.integer :topic_id, null: false
        t.integer :actor_id, null: false
        t.string :subject_type, null: false
        t.integer :subject_id, null: false
        t.string :action, null: false
        t.string :previous_access_level
        t.string :new_access_level
        t.jsonb :metadata, null: false, default: {}
        t.timestamps
      end
    end

    add_index :private_topic_access_events, :topic_id unless index_exists?(:private_topic_access_events, :topic_id)
    add_index :private_topic_access_events, :actor_id unless index_exists?(:private_topic_access_events, :actor_id)
    unless index_exists?(:private_topic_access_events, %i[subject_type subject_id])
      add_index :private_topic_access_events, %i[subject_type subject_id]
    end

    unless foreign_key_exists?(:private_topic_access_events, :topics, column: :topic_id)
      add_foreign_key :private_topic_access_events, :topics, column: :topic_id, on_delete: :cascade
    end

    unless foreign_key_exists?(:private_topic_access_events, :users, column: :actor_id)
      add_foreign_key :private_topic_access_events, :users, column: :actor_id
    end
  end

  def down
    remove_foreign_key :private_topic_access_events, column: :actor_id if foreign_key_exists?(:private_topic_access_events, :users, column: :actor_id)
    remove_foreign_key :private_topic_access_events, column: :topic_id if foreign_key_exists?(:private_topic_access_events, :topics, column: :topic_id)

    remove_index :private_topic_access_events, column: %i[subject_type subject_id] if index_exists?(:private_topic_access_events, %i[subject_type subject_id])
    remove_index :private_topic_access_events, :actor_id if index_exists?(:private_topic_access_events, :actor_id)
    remove_index :private_topic_access_events, :topic_id if index_exists?(:private_topic_access_events, :topic_id)

    drop_table :private_topic_access_events if table_exists?(:private_topic_access_events)
  end
end
