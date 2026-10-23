require "test_helper"
require_relative "../support/relational_helpers"

class RelationalSqlTest < ActiveSupport::TestCase
  test "foreign keys are enabled and absent parents are rejected directly" do
    assert_equal 1, User.connection.select_value("PRAGMA foreign_keys")
    assert_raises(ActiveRecord::InvalidForeignKey) { direct_insert(Task, user_id: 999, title: "Sem dono") }
    relational_user
    assert_raises(ActiveRecord::InvalidForeignKey) { direct_insert(Task, user_id: 1, project_id: 999, title: "Órfã") }
    assert_raises(ActiveRecord::InvalidForeignKey) { direct_insert(ProjectReference, user_id: 1, project_id: 999, title: "Órfã", kind: "material") }
    assert_empty User.connection.select_all("PRAGMA foreign_key_check").rows
  end

  test "composite foreign keys reject other owners even bypassing Rails" do
    project_for
    other = second_synthetic_user
    other_project = project_for(other)
    other_task = other.tasks.create!(title: "Outra")
    other_focus = prepared_focus(other)
    [ [ Task, { project_id: other_project.id, title: "x" } ],
      [ ProjectReference, { project_id: other_project.id, title: "x", kind: "material" } ],
      [ WidgetPlacement, { project_id: other_project.id, context: "project", widget_key: "tasks", position: 0, span: 5 } ],
      [ FocusSession, { project_id: other_project.id } ],
      [ FocusSession, { task_id: other_task.id } ],
      [ FocusCommand, { focus_session_id: other_focus.id, command_id: "x", kind: "start", expected_lock_version: 0, request_digest: "a" * 64, parameters: {}, result: {} } ] ].each do |model, attributes|
      assert_raises(ActiveRecord::InvalidForeignKey) { direct_insert(model, user_id: 1, **attributes) }
    end
    assert_equal 0, User.connection.select_value("PRAGMA ignore_check_constraints")
  end

  test "SQL enforces public UID uniqueness and immutable identity" do
    project = project_for(uid: "1")
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(Project, user_id: 1, uid: "1", name: "Outra", name_key: "outra") }
    assert_raises(ActiveRecord::StatementInvalid) { Project.where(id: project.id).update_all(uid: "replacement") }
    assert_raises(ActiveRecord::StatementInvalid) { Project.where(id: project.id).update_all(user_id: 2) }
    assert_equal "1", project.reload.uid
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(Task, user_id: 1, uid: " ", title: "Inválida") }
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(Project, user_id: 1, name: "Mesmo", name_key: project.name_key) }
  end

  test "SQL archive protection covers insert update delete and restoration" do
    project = project_for(status: "paused")
    task = relational_user.tasks.create!(project: project, title: "Preservada")
    reference = relational_user.project_references.create!(project: project, title: "Livro", kind: "material")
    project.archive!
    assert_raises(ActiveRecord::StatementInvalid) { Task.where(id: task.id).update_all(status: "completed") }
    assert_raises(ActiveRecord::StatementInvalid) { ProjectReference.where(id: reference.id).delete_all }
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(Task, user_id: 1, project_id: project.id, title: "Nova") }
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(ProjectReference, user_id: 1, project_id: project.id, title: "Nova", kind: "material") }
    assert_raises(ActiveRecord::StatementInvalid) { Project.where(id: project.id).update_all(name: "Mudança") }
    assert_raises(ActiveRecord::StatementInvalid) { Project.where(id: project.id).update_all(status: "active", archived_from: nil, archived_at: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { Project.where(id: project.id).delete_all }
    project.restore!
    assert_equal "paused", project.reload.status
    assert_equal "pending", task.reload.status
    assert ProjectReference.exists?(reference.id)
  end

  test "SQL rejects invalid catalogs booleans positions URLs and versions" do
    project = project_for
    [ [ Task, { title: "x", priority: "urgent" } ], [ Task, { title: "x", position: -1 } ],
      [ Task, { title: "x", lock_version: -1 } ], [ Task, { title: "" } ],
      [ ProjectReference, { project_id: project.id, title: "x", url: "javascript:alert(1)" } ],
      [ ProjectReference, { project_id: project.id, title: "x", url: "" } ],
      [ UserPreference, { accent: "red;display:none" } ], [ UserPreference, { music_enabled: nil } ],
      [ DockShortcut, { module_key: "unknown", position: 0 } ], [ DockShortcut, { module_key: "tasks", position: -1 } ],
      [ WidgetPlacement, { widget_key: "tasks", position: 0, span: 7 } ],
      [ WidgetPlacement, { widget_key: "info", position: 0, span: 5 } ],
      [ WidgetPlacement, { widget_key: "tasks", position: 0, span: 5, context: "home", project_id: project.id } ] ].each do |model, attributes|
      assert_raises(ActiveRecord::StatementInvalid) { direct_insert(model, user_id: 1, **attributes) }
    end
  end

  test "partial widget indexes enforce separate home and project contexts" do
    first = project_for
    second = project_for
    attributes = { user_id: 1, widget_key: "tasks", position: 0, span: 5 }
    direct_insert(WidgetPlacement, **attributes)
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(WidgetPlacement, **attributes) }
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(WidgetPlacement, **attributes.merge(widget_key: "focus")) }
    direct_insert(WidgetPlacement, **attributes.merge(context: "project", project_id: first.id))
    direct_insert(WidgetPlacement, **attributes.merge(context: "project", project_id: second.id))
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(WidgetPlacement, **attributes.merge(context: "project", project_id: first.id)) }
    sql = User.connection.select_values("SELECT sql FROM sqlite_master WHERE name IN ('widget_home_key','widget_home_position','widget_project_key','widget_project_position')")
    assert_equal 4, sql.size
    assert sql.all? { |definition| definition.include?("UNIQUE") && definition.include?("WHERE") }
  end

  test "SQL enforces single preference and dock keys and positions" do
    relational_user.create_user_preference!
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(UserPreference, user_id: 1) }
    direct_insert(DockShortcut, user_id: 1, module_key: "tasks", position: 0)
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(DockShortcut, user_id: 1, module_key: "tasks", position: 1) }
    assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(DockShortcut, user_id: 1, module_key: "focus", position: 0) }
  end

  test "SQL rejects a second occupant but accepts historical terminal sessions" do
    session = prepared_focus
    %w[ready running paused awaiting_confirmation].each do |status|
      attributes = { user_id: 1, status: status }
      attributes[:started_at] = Time.current unless status == "ready"
      attributes.merge!(running_since: Time.current, deadline_at: 25.minutes.from_now) if status == "running"
      attributes[:paused_at] = Time.current if status == "paused"
      attributes[:elapsed_seconds] = 1500 if status == "awaiting_confirmation"
      assert_raises(ActiveRecord::RecordNotUnique) { direct_insert(FocusSession, **attributes) }
    end
    direct_insert(FocusSession, user_id: 1, status: "cancelled", ended_at: Time.current)
    terminal = FocusSession.find_by!(status: "cancelled")
    assert_raises(ActiveRecord::StatementInvalid) { FocusSession.where(id: terminal.id).update_all(status: "ready", ended_at: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { FocusSession.where(id: terminal.id).delete_all }
    assert_equal 1, FocusSession.occupying.count
    assert_equal "ready", session.reload.status
    index = User.connection.select_value("SELECT sql FROM sqlite_master WHERE name = 'one_global_focus'")
    assert_includes index, "UNIQUE"
    assert_includes index, "WHERE"
  end

  test "SQL rejects inconsistent focus timing and command payloads" do
    relational_user
    [ { status: "running" }, { status: "completed" }, { elapsed_seconds: -1 }, { duration_seconds: 60 },
      { status: "ready", started_at: Time.current }, { elapsed_seconds: 1501 } ].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) { direct_insert(FocusSession, user_id: 1, **attributes) }
    end
    session = prepared_focus
    attributes = { user_id: 1, focus_session_id: session.id, command_id: "x", kind: "start", expected_lock_version: 0, request_digest: "a" * 64, parameters: {}, result: {} }
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(FocusCommand, **attributes.merge(kind: "toggle")) }
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(FocusCommand, **attributes.merge(result: [])) }
  end

  test "archived focus context permits cancellation but blocks fresh work and edits" do
    project = project_for
    session = prepared_focus(project: project)
    project.archive!
    assert_raises(ActiveRecord::StatementInvalid) { FocusSession.where(id: session.id).update_all(duration_seconds: 2700) }
    assert_raises(ActiveRecord::StatementInvalid) do
      FocusSession.where(id: session.id).update_all(status: "running", started_at: Time.current, running_since: Time.current, deadline_at: 25.minutes.from_now)
    end
    assert_raises(ActiveRecord::StatementInvalid) { direct_insert(FocusSession, user_id: 1, project_id: project.id) }
    session.reload.update!(status: "cancelled", ended_at: Time.current, end_reason: "cancelled")
    assert_empty FocusSession.occupying
    assert_equal "archived", project.reload.status
  end
end
