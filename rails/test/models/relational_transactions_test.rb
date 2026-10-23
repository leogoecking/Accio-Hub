require "test_helper"
require_relative "../support/relational_helpers"

class RelationalTransactionsTest < ActiveSupport::TestCase
  test "preference initialization is atomic and preserves recovery snapshot" do
    relational_user
    assert_raises(ActiveRecord::RecordInvalid) do
      UserPreference.transaction do
        relational_user.create_user_preference!(initialized_at: Time.current, legacy_cookie_backup: { "theme" => "light" }, legacy_cookie_digest: "a" * 64)
        relational_user.dock_shortcuts.create!(module_key: "tasks", position: 0)
        relational_user.widget_placements.create!(widget_key: "tasks", position: 0, span: 7)
      end
    end
    assert_equal 0, UserPreference.count
    assert_equal 0, DockShortcut.count
    assert_equal 0, WidgetPlacement.count
    preference = relational_user.reload.create_user_preference!(legacy_cookie_backup: { "theme" => "light" })
    preference.update!(theme: "light")
    assert_equal({ "theme" => "light" }, preference.reload.legacy_cookie_backup)
  end

  test "dock reorder avoids unique collisions and rejects stale browser snapshots" do
    preference = relational_user.create_user_preference!
    keys = %w[tasks focus projects]
    keys.each_with_index { |key, i| relational_user.dock_shortcuts.create!(module_key: key, position: i) }
    ids = DockShortcut.order(:position).pluck(:id)
    rows = DockShortcut.reorder!(user: relational_user, module_keys: keys.reverse, expected_version: preference.lock_version)
    assert_equal keys.reverse, rows.map(&:module_key)
    assert_equal [ 0, 1, 2 ], rows.map(&:position)
    assert_equal ids.reverse, rows.map(&:id)
    assert_raises(ActiveRecord::StaleObjectError) { DockShortcut.reorder!(user: relational_user, module_keys: keys, expected_version: 0) }
    assert_equal keys.reverse, DockShortcut.order(:position).pluck(:module_key)
    assert_raises(ArgumentError) { DockShortcut.reorder!(user: relational_user, module_keys: [ "tasks", "tasks", "focus" ], expected_version: preference.reload.lock_version) }
  end

  test "widget reorder preserves spans visibility and IDs across contexts" do
    preference = relational_user.create_user_preference!
    project = project_for
    keys = %w[tasks focus]
    keys.each_with_index { |key, i| relational_user.widget_placements.create!(widget_key: key, position: i, span: i.zero? ? 5 : 3, visible: i.zero?) }
    contextual = relational_user.widget_placements.create!(context: "project", project: project, widget_key: "tasks", position: 0, span: 12)
    before = WidgetPlacement.where(context: "home").pluck(:id, :span, :visible).sort
    rows = WidgetPlacement.reorder!(user: relational_user, widget_keys: keys.reverse, expected_version: preference.lock_version)
    assert_equal keys.reverse, rows.map(&:widget_key)
    assert_equal before, rows.map { |r| [ r.id, r.span, r.visible ] }.sort
    assert_equal 0, contextual.reload.position
  end

  test "reorder failure restores preference version and all intermediate positions" do
    preference = relational_user.create_user_preference!
    project = project_for
    %w[tasks focus].each_with_index { |key, i| relational_user.widget_placements.create!(context: "project", project: project, widget_key: key, position: i, span: 5) }
    original = WidgetPlacement.order(:id).map(&:attributes)
    WidgetPlacement.connection.execute("CREATE TRIGGER test_fail_widget_position BEFORE UPDATE ON widget_placements WHEN NEW.widget_key = 'focus' AND NEW.position = 0 BEGIN SELECT RAISE(ABORT, 'Synthetic failure after temporary positions'); END")
    assert_raises(ActiveRecord::StatementInvalid) do
      WidgetPlacement.reorder!(user: relational_user, context: "project", project: project, widget_keys: %w[focus tasks], expected_version: preference.lock_version)
    end
    assert_equal 0, preference.reload.lock_version
    assert_equal original, WidgetPlacement.order(:id).map(&:attributes)
  ensure
    WidgetPlacement.connection.execute("DROP TRIGGER IF EXISTS test_fail_widget_position")
  end

  test "empty widget reorders cannot bypass archived or foreign context guards" do
    preference = relational_user.create_user_preference!
    archived = project_for
    archived.archive!
    foreign = Project.create!(user: second_synthetic_user, name: "Outro proprietário")
    [ archived, foreign ].each do |project|
      assert_raises(ArgumentError) do
        WidgetPlacement.reorder!(user: relational_user, context: "project", project: project, widget_keys: [], expected_version: 0)
      end
    end
    assert_raises(ArgumentError) { WidgetPlacement.reorder!(user: relational_user, context: "project", widget_keys: [], expected_version: 0) }
    assert_equal 0, preference.reload.lock_version
  end

  test "failed transaction restores archived status and untouched children" do
    project = project_for
    task = relational_user.tasks.create!(project: project, title: "Original")
    assert_raises(RuntimeError) do
      Project.transaction do
        project.archive!
        raise "Synthetic failure"
      end
    end
    assert_equal "active", project.reload.status
    assert_nil project.archived_from
    assert_equal 0, project.lock_version
    assert_equal "Original", task.reload.title
  end

  test "focus receipt and effect commit once and incompatible retries are rejected" do
    session = prepared_focus
    count = 0
    options = { user: relational_user, command_id: "operation-1", kind: "start", focus_session: session, expected_version: 0, parameters: { "b" => 2, "a" => 1 } }
    receipt = FocusCommand.record!(**options) do |record|
      count += 1
      record.update!(status: "running", started_at: Time.current, running_since: Time.current, deadline_at: 25.minutes.from_now)
      { "session_uid" => record.uid, "version" => record.lock_version }
    end
    replay = FocusCommand.record!(**options.merge(parameters: { "a" => 1, "b" => 2 })) { flunk "Retry must not reapply" }
    assert_equal 1, count
    assert_equal receipt.id, replay.id
    assert_equal receipt.result, replay.result
    assert_equal 1, session.reload.lock_version
    assert_raises(FocusCommand::IncompatibleRetry) { FocusCommand.record!(**options.merge(kind: "reset")) { flunk } }
    assert_raises(FocusCommand::IncompatibleRetry) { FocusCommand.record!(**options.merge(parameters: { "a" => 2 })) { flunk } }
    assert_raises(ActiveRecord::StaleObjectError) { FocusCommand.record!(**options.merge(command_id: "operation-2")) { flunk } }
    assert_raises(ActiveRecord::ReadOnlyRecord) { receipt.update!(result: {}) }
    assert_raises(ActiveRecord::StatementInvalid) { FocusCommand.where(id: receipt.id).update_all(result: {}) }
    assert_raises(ActiveRecord::StatementInvalid) { FocusCommand.where(id: receipt.id).delete_all }
    assert_equal 1, FocusCommand.count
  end

  test "failure before receipt completion rolls back effect and permits safe retry" do
    session = prepared_focus
    options = { user: relational_user, command_id: "failed", kind: "reset", focus_session: session, expected_version: 0 }
    assert_raises(ActiveRecord::RecordInvalid) do
      FocusCommand.record!(**options) do |record|
        record.update!(duration_seconds: 2700)
        [] # Invalid receipt: effect must roll back too.
      end
    end
    assert_equal 1500, session.reload.duration_seconds
    assert_equal 0, session.lock_version
    assert_equal 0, FocusCommand.count
    receipt = FocusCommand.record!(**options) { |record| record.update!(duration_seconds: 2700); { "duration" => 2700 } }
    assert_equal 2700, session.reload.duration_seconds
    assert_equal({ "duration" => 2700 }, receipt.result)
  end

  test "focus contexts belong to the task at creation and stay historical after moving task" do
    first = project_for
    second = project_for
    task = relational_user.tasks.create!(project: first, title: "Contexto")
    assert_not relational_user.focus_sessions.new(project: second, task: task).valid?
    session = prepared_focus(project: first, task: task)
    task.update!(project: second)
    session.update!(duration_seconds: 2700)
    assert_equal first.id, session.reload.project_id
    assert_raises(ActiveRecord::ReadonlyAttributeError) { session.update!(project: second) }
    first.archive!
    assert_raises(ActiveRecord::RecordInvalid) { session.update!(duration_seconds: 1500) }
    # Cancelling existing global focus releases the timer without editing project content.
    session.reload.update!(status: "cancelled", ended_at: Time.current, end_reason: "cancelled")
    assert_not relational_user.focus_sessions.new(project: first).valid?
  end
end
