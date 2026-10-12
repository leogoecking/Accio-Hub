class CreatePreferencesAndPlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :theme, null: false, default: "dark"
      t.string :wallpaper, null: false, default: "northern"
      t.string :accent, null: false, default: "#b1f07d"
      t.string :density, null: false, default: "comfortable"
      t.boolean :music_enabled, null: false, default: true
      t.boolean :music_expanded, null: false, default: false
      t.integer :focus_duration_seconds, null: false, default: 1500
      t.string :project_library_status, null: false, default: "all"
      t.string :project_library_sort, null: false, default: "name"
      t.boolean :project_library_favorites_only, null: false, default: false
      t.integer :preferences_schema_version, null: false, default: 1
      t.datetime :initialized_at
      t.datetime :legacy_cookie_imported_at
      t.string :legacy_cookie_digest
      t.json :legacy_cookie_backup
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :user_preferences, "theme IN ('dark','light') AND wallpaper IN ('northern','ember','ocean','graphite') AND density = 'comfortable'", name: "preference_appearance"
    add_check_constraint :user_preferences, "length(accent) = 7 AND substr(accent,1,1) = '#' AND substr(accent,2) NOT GLOB '*[^0-9a-fA-F]*'", name: "preference_accent"
    add_check_constraint :user_preferences, "music_enabled IN (0,1) AND music_expanded IN (0,1) AND project_library_favorites_only IN (0,1)", name: "preference_booleans"
    add_check_constraint :user_preferences, "focus_duration_seconds IN (1500,2700) AND project_library_status IN ('all','active','paused','archived') AND project_library_sort IN ('name','recent')", name: "preference_catalog"
    add_check_constraint :user_preferences, "typeof(preferences_schema_version) = 'integer' AND preferences_schema_version > 0 AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "preference_versions"
    add_check_constraint :user_preferences, "legacy_cookie_digest IS NULL OR (length(legacy_cookie_digest) = 64 AND legacy_cookie_digest NOT GLOB '*[^0-9a-f]*')", name: "preference_digest"
    add_check_constraint :user_preferences, "legacy_cookie_backup IS NULL OR (json_valid(legacy_cookie_backup) AND json_type(legacy_cookie_backup) = 'object')", name: "preference_backup"

    create_table :dock_shortcuts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :module_key, null: false
      t.integer :position, null: false
      t.boolean :visible, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :dock_shortcuts, [ :user_id, :module_key ], unique: true
    add_index :dock_shortcuts, [ :user_id, :position ], unique: true
    add_check_constraint :dock_shortcuts, "module_key IN ('tasks','calendar','focus','knowledge','projects','feed','backup','email')", name: "dock_catalog"
    add_check_constraint :dock_shortcuts, "typeof(position) = 'integer' AND position >= 0 AND visible IN (0,1) AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "dock_values"

    create_table :widget_placements do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :project_id
      t.string :context, null: false, default: "home"
      t.string :widget_key, null: false
      t.integer :position, null: false
      t.integer :span, null: false
      t.boolean :visible, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :widget_placements, :projects, column: [ :user_id, :project_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_check_constraint :widget_placements, "(context = 'home' AND project_id IS NULL) OR (context = 'project' AND project_id IS NOT NULL)", name: "widget_context"
    add_check_constraint :widget_placements, "widget_key IN ('tasks','focus','calendar','feed','notes','backup','projects','info') AND span IN (3,4,5,6,8,12)", name: "widget_catalog"
    add_check_constraint :widget_placements, "(context = 'home' AND widget_key IN ('tasks','focus','calendar','feed','notes','backup','projects')) OR (context = 'project' AND widget_key IN ('tasks','focus','notes','info'))", name: "widget_context_catalog"
    add_check_constraint :widget_placements, "typeof(position) = 'integer' AND position >= 0 AND visible IN (0,1) AND typeof(lock_version) = 'integer' AND lock_version >= 0", name: "widget_values"
    add_index :widget_placements, [ :user_id, :widget_key ], unique: true, where: "context = 'home'", name: "widget_home_key"
    add_index :widget_placements, [ :user_id, :position ], unique: true, where: "context = 'home'", name: "widget_home_position"
    add_index :widget_placements, [ :user_id, :project_id, :widget_key ], unique: true, where: "context = 'project'", name: "widget_project_key"
    add_index :widget_placements, [ :user_id, :project_id, :position ], unique: true, where: "context = 'project'", name: "widget_project_position"
  end
end
