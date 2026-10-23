class CreateProjectsAndTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.text :uid, null: false
      t.string :name, null: false
      t.string :name_key, null: false
      t.text :description, null: false, default: ""
      t.string :icon, null: false, default: "grid"
      t.string :tint, null: false, default: "mint"
      t.string :color
      t.string :status, null: false, default: "active"
      t.string :archived_from
      t.datetime :archived_at
      t.datetime :last_activity_at
      t.boolean :favorite, null: false, default: false
      t.integer :lock_version, null: false, default: 0
      t.datetime :origin_created_at
      t.datetime :origin_updated_at
      t.timestamps
    end
    add_identity :projects
    add_index :projects, [ :user_id, :name_key ], unique: true
    add_index :projects, [ :user_id, :status ]
    add_index :projects, [ :user_id, :last_activity_at ]
    add_check_constraint :projects, "length(trim(name)) BETWEEN 1 AND 80 AND length(name_key) > 0 AND length(description) <= 500", name: "project_text"
    add_check_constraint :projects, "status IN ('active','paused','archived') AND (archived_from IS NULL OR archived_from IN ('active','paused')) AND (status = 'archived' OR (archived_from IS NULL AND archived_at IS NULL))", name: "project_status"
    add_check_constraint :projects, "icon IN ('grid','code','book','target','rss','calendar','cloud','music','check','mail') AND tint IN ('mint','purple','pink','blue','orange','gold')", name: "project_catalog"
    add_check_constraint :projects, "color IS NULL OR (length(color) = 7 AND substr(color,1,1) = '#' AND substr(color,2) NOT GLOB '*[^0-9a-fA-F]*')", name: "project_color"
    add_check_constraint :projects, "favorite IN (0,1)", name: "project_favorite"

    create_table :tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.text :uid, null: false
      t.integer :project_id
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.string :priority, null: false, default: "normal"
      t.datetime :completed_at
      t.integer :position, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.datetime :origin_created_at
      t.datetime :origin_updated_at
      t.timestamps
    end
    add_identity :tasks
    add_foreign_key :tasks, :projects, column: [ :user_id, :project_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_index :tasks, [ :user_id, :status, :position ]
    add_index :tasks, [ :user_id, :project_id, :status, :position ]
    add_check_constraint :tasks, "length(trim(title)) BETWEEN 1 AND 120", name: "task_title"
    add_check_constraint :tasks, "status IN ('pending','completed') AND priority IN ('normal','high') AND (status = 'completed' OR completed_at IS NULL)", name: "task_status"
    add_check_constraint :tasks, "typeof(position) = 'integer' AND position >= 0", name: "task_position"

    create_table :project_references do |t|
      t.references :user, null: false, foreign_key: true
      t.text :uid, null: false
      t.integer :project_id, null: false
      t.string :title, null: false
      t.string :kind, null: false, default: "link"
      t.text :url, null: false, default: ""
      t.text :description, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.datetime :origin_created_at
      t.datetime :origin_updated_at
      t.timestamps
    end
    add_identity :project_references
    add_foreign_key :project_references, :projects, column: [ :user_id, :project_id ], primary_key: [ :user_id, :id ], on_delete: :restrict
    add_index :project_references, [ :user_id, :project_id, :position ], name: "reference_project_order"
    add_check_constraint :project_references, "length(trim(title)) BETWEEN 1 AND 120 AND length(description) <= 2000", name: "reference_text"
    add_check_constraint :project_references, "kind IN ('link','material') AND (kind != 'link' OR length(trim(url)) > 0) AND (url = '' OR lower(url) LIKE 'http://%' OR lower(url) LIKE 'https://%')", name: "reference_url"
    add_check_constraint :project_references, "typeof(position) = 'integer' AND position >= 0", name: "reference_position"
  end

  private

  def add_identity(table)
    add_index table, [ :user_id, :uid ], unique: true
    add_index table, [ :user_id, :id ], unique: true
    add_check_constraint table, "length(trim(uid, char(9)||char(10)||char(13)||' ')) > 0 AND instr(uid, char(0)) = 0", name: "#{table}_uid"
    add_check_constraint table, "typeof(lock_version) = 'integer' AND lock_version >= 0", name: "#{table}_version"
  end
end
