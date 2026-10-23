# Read-only post-browser integrity check; synthetic fixture database only.
require "json"
workspace = ENV.fetch("ACCIO_QA_WORKSPACE")
abort "Synthetic QA database required" unless Rails.env.development? && workspace.start_with?(Rails.root.join("tmp/p12d-browser-").to_s) && ActiveRecord::Base.connection_db_config.database == File.join(workspace, "synthetic.sqlite3")
user = User.first
abort "Wrong synthetic account" unless user.email_address == "qa@example.test"
legacy = user.projects.find_by!(uid: "42/á?%#项目")
original = JSON.parse(File.read(File.join(workspace, "d1-snapshot.json"))).fetch("projects").find { |p| p["uid"] == legacy.uid }
fields = %w[uid user_id created_at origin_created_at origin_updated_at tint color]
raise "Legacy identity/dates/color changed" unless legacy.attributes.as_json.slice(*fields) == original.slice(*fields)
raise "Unexpected project counts" unless user.projects.count == 5 && user.projects.where(name: "Projeto Navegador QA local").count == 1 && user.projects.where(name: "Projeto direto QA").count == 1
children = [ user.tasks.where(project: legacy), user.project_references.where(project: legacy), user.widget_placements.where(project: legacy), user.focus_sessions.where(project: legacy) ]
raise "Related records lost" unless children.map(&:count) == [ 1, 2, 1, 1 ]
raise "Read-only rows changed" unless children.flat_map(&:to_a).all? { |row| row.lock_version.zero? && row.created_at == row.updated_at }
raise "Focus became functional" unless user.focus_sessions.count == 1 && user.focus_sessions.first.status == "ready"
connection = ActiveRecord::Base.connection
raise "Foreign key violations" unless connection.select_all("PRAGMA foreign_key_check").rows.empty?
raise "SQL guards changed" unless connection.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'accio_%'") == 25
puts JSON.pretty_generate({ projects: 5, unique_confirmed_creation: true, legacy_identity_dates_tint_and_null_color_preserved: true,
  children: { tasks: 1, references: 2, project_widgets: 1, focus: 1 }, children_versions_and_dates_unchanged: true,
  focus_interface_has_no_persistence_effects: true, foreign_keys_intact: true, sql_triggers: 25 })
