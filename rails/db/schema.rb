# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_12_040000) do
  create_table "auth_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_auth_sessions_on_user_id"
  end

  create_table "dock_shortcuts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "module_key", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible", default: true, null: false
    t.index ["user_id", "module_key"], name: "index_dock_shortcuts_on_user_id_and_module_key", unique: true
    t.index ["user_id", "position"], name: "index_dock_shortcuts_on_user_id_and_position", unique: true
    t.index ["user_id"], name: "index_dock_shortcuts_on_user_id"
    t.check_constraint "module_key IN ('tasks','calendar','focus','knowledge','projects','feed','backup','email')", name: "dock_catalog"
    t.check_constraint "typeof(position) = 'integer' AND position >= 0 AND visible IN (0,1) AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "dock_values"
  end

  create_table "focus_commands", force: :cascade do |t|
    t.text "command_id", null: false
    t.datetime "created_at", null: false
    t.integer "expected_lock_version", null: false
    t.integer "focus_session_id", null: false
    t.string "kind", null: false
    t.json "parameters", null: false
    t.string "request_digest", null: false
    t.json "result", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "command_id"], name: "index_focus_commands_on_user_id_and_command_id", unique: true
    t.index ["user_id", "focus_session_id"], name: "index_focus_commands_on_user_id_and_focus_session_id"
    t.index ["user_id"], name: "index_focus_commands_on_user_id"
    t.check_constraint "json_valid(parameters) AND json_type(parameters) = 'object' AND json_valid(result) AND json_type(result) = 'object'", name: "command_json"
    t.check_constraint "length(request_digest) = 64 AND request_digest NOT GLOB '*[^0-9a-f]*'", name: "command_digest"
    t.check_constraint "length(trim(command_id)) > 0 AND instr(command_id,char(0)) = 0 AND kind IN ('start','pause','reset','complete') AND typeof(expected_lock_version) = 'integer' AND expected_lock_version >= 0", name: "command_contract"
  end

  create_table "focus_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "deadline_at"
    t.integer "duration_seconds", default: 1500, null: false
    t.integer "elapsed_seconds", default: 0, null: false
    t.string "end_reason"
    t.datetime "ended_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "paused_at"
    t.integer "project_id"
    t.datetime "running_since"
    t.datetime "started_at"
    t.string "status", default: "ready", null: false
    t.integer "task_id"
    t.text "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "id"], name: "index_focus_sessions_on_user_id_and_id", unique: true
    t.index ["user_id", "status", "completed_at"], name: "index_focus_sessions_on_user_id_and_status_and_completed_at"
    t.index ["user_id", "uid"], name: "index_focus_sessions_on_user_id_and_uid", unique: true
    t.index ["user_id"], name: "index_focus_sessions_on_user_id"
    t.index ["user_id"], name: "one_global_focus", unique: true, where: "status IN ('ready','running','paused','awaiting_confirmation')"
    t.check_constraint "(status = 'completed' AND completed_at IS NOT NULL) OR (status != 'completed' AND completed_at IS NULL)", name: "focus_completed"
    t.check_constraint "(status = 'paused' AND paused_at IS NOT NULL) OR (status != 'paused' AND paused_at IS NULL)", name: "focus_paused"
    t.check_constraint "(status = 'running' AND running_since IS NOT NULL AND deadline_at IS NOT NULL AND deadline_at > running_since) OR (status != 'running' AND running_since IS NULL AND deadline_at IS NULL)", name: "focus_segment"
    t.check_constraint "(status IN ('completed','cancelled') AND ended_at IS NOT NULL) OR (status NOT IN ('completed','cancelled') AND ended_at IS NULL)", name: "focus_ended"
    t.check_constraint "duration_seconds IN (1500,2700) AND typeof(elapsed_seconds) = 'integer' AND elapsed_seconds BETWEEN 0 AND duration_seconds AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "focus_durations"
    t.check_constraint "end_reason IS NULL OR (status = 'cancelled' AND end_reason IN ('reset','cancelled','interrupted'))", name: "focus_reason"
    t.check_constraint "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "focus_uid"
    t.check_constraint "status != 'ready' OR (elapsed_seconds = 0 AND started_at IS NULL)", name: "focus_ready"
    t.check_constraint "status IN ('ready','running','paused','awaiting_confirmation','completed','cancelled')", name: "focus_status"
    t.check_constraint "status NOT IN ('awaiting_confirmation','completed') OR elapsed_seconds = duration_seconds", name: "focus_elapsed"
    t.check_constraint "status NOT IN ('running','paused','awaiting_confirmation','completed') OR started_at IS NOT NULL", name: "focus_started"
  end

  create_table "project_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.string "kind", default: "link", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "origin_created_at"
    t.datetime "origin_updated_at"
    t.integer "position", default: 0, null: false
    t.integer "project_id", null: false
    t.string "title", null: false
    t.text "uid", null: false
    t.datetime "updated_at", null: false
    t.text "url", default: "", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "id"], name: "index_project_references_on_user_id_and_id", unique: true
    t.index ["user_id", "project_id", "position"], name: "reference_project_order"
    t.index ["user_id", "uid"], name: "index_project_references_on_user_id_and_uid", unique: true
    t.index ["user_id"], name: "index_project_references_on_user_id"
    t.check_constraint "kind IN ('link','material') AND (kind != 'link' OR length(trim(url)) > 0) AND (url = '' OR lower(url) LIKE 'http://%' OR lower(url) LIKE 'https://%')", name: "reference_url"
    t.check_constraint "length(trim(title)) BETWEEN 1 AND 120 AND length(description) <= 2000", name: "reference_text"
    t.check_constraint "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "project_references_uid"
    t.check_constraint "typeof(lock_version) = 'integer' AND lock_version >= 0", name: "project_references_version"
    t.check_constraint "typeof(position) = 'integer' AND position >= 0", name: "reference_position"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "archived_from"
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.boolean "favorite", default: false, null: false
    t.string "icon", default: "grid", null: false
    t.datetime "last_activity_at"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.string "name_key", null: false
    t.datetime "origin_created_at"
    t.datetime "origin_updated_at"
    t.string "status", default: "active", null: false
    t.string "tint", default: "mint", null: false
    t.text "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "id"], name: "index_projects_on_user_id_and_id", unique: true
    t.index ["user_id", "last_activity_at"], name: "index_projects_on_user_id_and_last_activity_at"
    t.index ["user_id", "name_key"], name: "index_projects_on_user_id_and_name_key", unique: true
    t.index ["user_id", "status"], name: "index_projects_on_user_id_and_status"
    t.index ["user_id", "uid"], name: "index_projects_on_user_id_and_uid", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
    t.check_constraint "color IS NULL OR (length(color) = 7 AND substr(color,1,1) = '#' AND substr(color,2) NOT GLOB '*[^0-9a-fA-F]*')", name: "project_color"
    t.check_constraint "favorite IN (0,1)", name: "project_favorite"
    t.check_constraint "icon IN ('grid','code','book','target','rss','calendar','cloud','music','check','mail') AND tint IN ('mint','purple','pink','blue','orange','gold')", name: "project_catalog"
    t.check_constraint "length(trim(name)) BETWEEN 1 AND 80 AND length(name_key) > 0 AND length(description) <= 500", name: "project_text"
    t.check_constraint "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "projects_uid"
    t.check_constraint "status IN ('active','paused','archived') AND (archived_from IS NULL OR archived_from IN ('active','paused')) AND (status = 'archived' OR (archived_from IS NULL AND archived_at IS NULL))", name: "project_status"
    t.check_constraint "typeof(lock_version) = 'integer' AND lock_version >= 0", name: "projects_version"
  end

  create_table "tasks", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "origin_created_at"
    t.datetime "origin_updated_at"
    t.integer "position", default: 0, null: false
    t.string "priority", default: "normal", null: false
    t.integer "project_id"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.text "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "id"], name: "index_tasks_on_user_id_and_id", unique: true
    t.index ["user_id", "project_id", "status", "position"], name: "index_tasks_on_user_id_and_project_id_and_status_and_position"
    t.index ["user_id", "status", "position"], name: "index_tasks_on_user_id_and_status_and_position"
    t.index ["user_id", "uid"], name: "index_tasks_on_user_id_and_uid", unique: true
    t.index ["user_id"], name: "index_tasks_on_user_id"
    t.check_constraint "length(trim(title)) BETWEEN 1 AND 120", name: "task_title"
    t.check_constraint "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "tasks_uid"
    t.check_constraint "status IN ('pending','completed') AND priority IN ('normal','high') AND (status = 'completed' OR completed_at IS NULL)", name: "task_status"
    t.check_constraint "typeof(lock_version) = 'integer' AND lock_version >= 0", name: "tasks_version"
    t.check_constraint "typeof(position) = 'integer' AND position >= 0", name: "task_position"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.string "accent", default: "#b1f07d", null: false
    t.datetime "created_at", null: false
    t.string "density", default: "comfortable", null: false
    t.integer "focus_duration_seconds", default: 1500, null: false
    t.datetime "initialized_at"
    t.json "legacy_cookie_backup"
    t.string "legacy_cookie_digest"
    t.datetime "legacy_cookie_imported_at"
    t.integer "lock_version", default: 0, null: false
    t.boolean "music_enabled", default: true, null: false
    t.boolean "music_expanded", default: false, null: false
    t.integer "preferences_schema_version", default: 1, null: false
    t.boolean "project_library_favorites_only", default: false, null: false
    t.string "project_library_sort", default: "name", null: false
    t.string "project_library_status", default: "all", null: false
    t.string "theme", default: "dark", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "wallpaper", default: "northern", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id", unique: true
    t.check_constraint "focus_duration_seconds IN (1500,2700) AND project_library_status IN ('all','active','paused','archived') AND project_library_sort IN ('name','recent')", name: "preference_catalog"
    t.check_constraint "legacy_cookie_backup IS NULL OR (json_valid(legacy_cookie_backup) AND json_type(legacy_cookie_backup) = 'object')", name: "preference_backup"
    t.check_constraint "legacy_cookie_digest IS NULL OR (length(legacy_cookie_digest) = 64 AND legacy_cookie_digest NOT GLOB '*[^0-9a-f]*')", name: "preference_digest"
    t.check_constraint "length(accent) = 7 AND substr(accent,1,1) = '#' AND substr(accent,2) NOT GLOB '*[^0-9a-fA-F]*'", name: "preference_accent"
    t.check_constraint "music_enabled IN (0,1) AND music_expanded IN (0,1) AND project_library_favorites_only IN (0,1)", name: "preference_booleans"
    t.check_constraint "theme IN ('dark','light') AND wallpaper IN ('northern','ember','ocean','graphite') AND density = 'comfortable'", name: "preference_appearance"
    t.check_constraint "typeof(preferences_schema_version) = 'integer' AND preferences_schema_version > 0 AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "preference_versions"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "id = 1", name: "one_administrator"
  end

  create_table "widget_placements", force: :cascade do |t|
    t.string "context", default: "home", null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "position", null: false
    t.integer "project_id"
    t.integer "span", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible", default: true, null: false
    t.string "widget_key", null: false
    t.index ["user_id", "position"], name: "widget_home_position", unique: true, where: "context = 'home'"
    t.index ["user_id", "project_id", "position"], name: "widget_project_position", unique: true, where: "context = 'project'"
    t.index ["user_id", "project_id", "widget_key"], name: "widget_project_key", unique: true, where: "context = 'project'"
    t.index ["user_id", "widget_key"], name: "widget_home_key", unique: true, where: "context = 'home'"
    t.index ["user_id"], name: "index_widget_placements_on_user_id"
    t.check_constraint "(context = 'home' AND project_id IS NULL) OR (context = 'project' AND project_id IS NOT NULL)", name: "widget_context"
    t.check_constraint "(context = 'home' AND widget_key IN ('tasks','focus','calendar','feed','notes','backup','projects')) OR (context = 'project' AND widget_key IN ('tasks','focus','notes','info'))", name: "widget_context_catalog"
    t.check_constraint "typeof(position) = 'integer' AND position >= 0 AND visible IN (0,1) AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "widget_values"
    t.check_constraint "widget_key IN ('tasks','focus','calendar','feed','notes','backup','projects','info') AND span IN (3,4,5,6,8,12)", name: "widget_catalog"
  end

  add_foreign_key "auth_sessions", "users"
  add_foreign_key "dock_shortcuts", "users"
  add_foreign_key "focus_commands", "focus_sessions", column: ["user_id", "focus_session_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "focus_commands", "users"
  add_foreign_key "focus_sessions", "projects", column: ["user_id", "project_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "focus_sessions", "tasks", column: ["user_id", "task_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "focus_sessions", "users"
  add_foreign_key "project_references", "projects", column: ["user_id", "project_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "project_references", "users"
  add_foreign_key "projects", "users"
  add_foreign_key "tasks", "projects", column: ["user_id", "project_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "tasks", "users"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "widget_placements", "projects", column: ["user_id", "project_id"], primary_key: ["user_id", "id"], on_delete: :restrict
  add_foreign_key "widget_placements", "users"
  execute "CREATE TRIGGER accio_command_immutable_delete BEFORE DELETE ON focus_commands\nWHEN 1\nBEGIN SELECT RAISE(ABORT, 'Recibo de comando é imutável'); END"
  execute "CREATE TRIGGER accio_command_immutable_update BEFORE UPDATE ON focus_commands\nWHEN 1\nBEGIN SELECT RAISE(ABORT, 'Recibo de comando é imutável'); END"
  execute "CREATE TRIGGER accio_dock_shortcuts_identity BEFORE UPDATE ON dock_shortcuts\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.module_key IS NOT OLD.module_key\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_focus_archived_context BEFORE INSERT ON focus_sessions\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Restaure o projeto antes de iniciar novo foco'); END"
  execute "CREATE TRIGGER accio_focus_archived_write BEFORE UPDATE ON focus_sessions\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived') AND NOT ((NEW.status IN ('paused','awaiting_confirmation','completed','cancelled') OR (NEW.status = 'running' AND OLD.status = 'running')) AND NEW.duration_seconds IS OLD.duration_seconds AND NEW.started_at IS OLD.started_at AND NEW.created_at IS OLD.created_at)\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado permite apenas encerrar ou reconciliar foco existente'); END"
  execute "CREATE TRIGGER accio_focus_delete BEFORE DELETE ON focus_sessions\nWHEN 1\nBEGIN SELECT RAISE(ABORT, 'Tentativas de foco são preservadas'); END"
  execute "CREATE TRIGGER accio_focus_sessions_identity BEFORE UPDATE ON focus_sessions\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.uid IS NOT OLD.uid OR NEW.project_id IS NOT OLD.project_id OR NEW.task_id IS NOT OLD.task_id\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_focus_task_context BEFORE INSERT ON focus_sessions\nWHEN NEW.task_id IS NOT NULL AND EXISTS (SELECT 1 FROM tasks WHERE id = NEW.task_id AND project_id IS NOT NEW.project_id)\nBEGIN SELECT RAISE(ABORT, 'Contexto deve ser o da tarefa'); END"
  execute "CREATE TRIGGER accio_focus_terminal BEFORE UPDATE ON focus_sessions\nWHEN OLD.status IN ('completed','cancelled')\nBEGIN SELECT RAISE(ABORT, 'Tentativa encerrada é imutável'); END"
  execute "CREATE TRIGGER accio_project_archived BEFORE UPDATE ON projects\nWHEN OLD.status = 'archived' AND NOT (NEW.status = coalesce(OLD.archived_from, 'active') AND NEW.archived_from IS NULL AND NEW.archived_at IS NULL AND NEW.user_id IS OLD.user_id AND NEW.uid IS OLD.uid AND NEW.name IS OLD.name AND NEW.name_key IS OLD.name_key AND NEW.description IS OLD.description AND NEW.icon IS OLD.icon AND NEW.tint IS OLD.tint AND NEW.color IS OLD.color AND NEW.favorite IS OLD.favorite AND NEW.created_at IS OLD.created_at AND NEW.origin_created_at IS OLD.origin_created_at AND NEW.origin_updated_at IS OLD.origin_updated_at)\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_project_delete BEFORE DELETE ON projects\nWHEN 1\nBEGIN SELECT RAISE(ABORT, 'Use arquivamento'); END"
  execute "CREATE TRIGGER accio_project_references_archived_delete BEFORE DELETE ON project_references\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_project_references_archived_insert BEFORE INSERT ON project_references\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_project_references_archived_update BEFORE UPDATE ON project_references\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived') OR EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_project_references_identity BEFORE UPDATE ON project_references\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.uid IS NOT OLD.uid\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_projects_identity BEFORE UPDATE ON projects\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.uid IS NOT OLD.uid\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_tasks_archived_delete BEFORE DELETE ON tasks\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_tasks_archived_insert BEFORE INSERT ON tasks\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_tasks_archived_update BEFORE UPDATE ON tasks\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived') OR EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_tasks_identity BEFORE UPDATE ON tasks\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.uid IS NOT OLD.uid\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_user_preferences_identity BEFORE UPDATE ON user_preferences\nWHEN NEW.user_id IS NOT OLD.user_id\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
  execute "CREATE TRIGGER accio_widget_placements_archived_delete BEFORE DELETE ON widget_placements\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_widget_placements_archived_insert BEFORE INSERT ON widget_placements\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_widget_placements_archived_update BEFORE UPDATE ON widget_placements\nWHEN EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived') OR EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')\nBEGIN SELECT RAISE(ABORT, 'Projeto arquivado é somente leitura'); END"
  execute "CREATE TRIGGER accio_widget_placements_identity BEFORE UPDATE ON widget_placements\nWHEN NEW.user_id IS NOT OLD.user_id OR NEW.context IS NOT OLD.context OR NEW.project_id IS NOT OLD.project_id OR NEW.widget_key IS NOT OLD.widget_key\nBEGIN SELECT RAISE(ABORT, 'Identidade e proprietário são imutáveis'); END"
end
