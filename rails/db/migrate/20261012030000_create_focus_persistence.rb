class CreateFocusPersistence < ActiveRecord::Migration[8.1]
  def change
    create_table :focus_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :uid, null: false
      t.integer :project_id
      t.integer :task_id
      t.string :status, null: false, default: "ready"
      t.integer :duration_seconds, null: false, default: 1500
      t.integer :elapsed_seconds, null: false, default: 0
      t.datetime :started_at
      t.datetime :running_since
      t.datetime :deadline_at
      t.datetime :paused_at
      t.datetime :completed_at
      t.datetime :ended_at
      t.string :end_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :focus_sessions, [ :user_id, :uid ], unique: true
    add_index :focus_sessions, [ :user_id, :id ], unique: true
    add_index :focus_sessions, [ :user_id, :status, :completed_at ]
    add_index :focus_sessions, :user_id, unique: true, where: "status IN ('ready','running','paused','awaiting_confirmation')", name: "one_global_focus"
    add_foreign_key :focus_sessions, :projects, column: [ :user_id, :project_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_foreign_key :focus_sessions, :tasks, column: [ :user_id, :task_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_check_constraint :focus_sessions, "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "focus_uid"
    add_check_constraint :focus_sessions, "status IN ('ready','running','paused','awaiting_confirmation','completed','cancelled')", name: "focus_status"
    add_check_constraint :focus_sessions, "duration_seconds IN (1500,2700) AND typeof(elapsed_seconds) = 'integer' AND elapsed_seconds BETWEEN 0 AND duration_seconds AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "focus_durations"
    add_check_constraint :focus_sessions, "(status = 'running' AND running_since IS NOT NULL AND deadline_at IS NOT NULL AND deadline_at > running_since) OR (status != 'running' AND running_since IS NULL AND deadline_at IS NULL)", name: "focus_segment"
    add_check_constraint :focus_sessions, "status NOT IN ('running','paused','awaiting_confirmation','completed') OR started_at IS NOT NULL", name: "focus_started"
    add_check_constraint :focus_sessions, "(status = 'paused' AND paused_at IS NOT NULL) OR (status != 'paused' AND paused_at IS NULL)", name: "focus_paused"
    add_check_constraint :focus_sessions, "(status = 'completed' AND completed_at IS NOT NULL) OR (status != 'completed' AND completed_at IS NULL)", name: "focus_completed"
    add_check_constraint :focus_sessions, "(status IN ('completed','cancelled') AND ended_at IS NOT NULL) OR (status NOT IN ('completed','cancelled') AND ended_at IS NULL)", name: "focus_ended"
    add_check_constraint :focus_sessions, "status NOT IN ('awaiting_confirmation','completed') OR elapsed_seconds = duration_seconds", name: "focus_elapsed"
    add_check_constraint :focus_sessions, "status != 'ready' OR (elapsed_seconds = 0 AND started_at IS NULL)", name: "focus_ready"
    add_check_constraint :focus_sessions, "end_reason IS NULL OR (status = 'cancelled' AND end_reason IN ('reset','cancelled','interrupted'))", name: "focus_reason"

    create_table :focus_commands do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :focus_session_id, null: false
      t.text :command_id, null: false
      t.string :kind, null: false
      t.integer :expected_lock_version, null: false
      t.string :request_digest, null: false
      t.json :parameters, null: false
      t.json :result, null: false
      t.timestamps
    end
    add_index :focus_commands, [ :user_id, :command_id ], unique: true
    add_index :focus_commands, [ :user_id, :focus_session_id ]
    add_foreign_key :focus_commands, :focus_sessions, column: [ :user_id, :focus_session_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_check_constraint :focus_commands, "length(trim(command_id)) > 0 AND instr(command_id,char(0)) = 0 AND kind IN ('start','pause','reset','complete') AND typeof(expected_lock_version) = 'integer' AND expected_lock_version >= 0", name: "command_contract"
    add_check_constraint :focus_commands, "length(request_digest) = 64 AND request_digest NOT GLOB '*[^0-9a-f]*'", name: "command_digest"
    add_check_constraint :focus_commands, "json_valid(parameters) AND json_type(parameters) = 'object' AND json_valid(result) AND json_type(result) = 'object'", name: "command_json"
  end
end
