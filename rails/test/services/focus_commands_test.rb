require "test_helper"
require_relative "../support/focus_helpers"
require_relative "../support/relational_helpers"

class FocusCommandsTest < ActiveSupport::TestCase
  include FocusHelpers
  setup { focus_setup }

  test "all state and action pairs preserve the existing machine contracts" do
    FocusSession::STATUSES.each do |status|
      %w[start resume pause reconcile resolve restart cancel confirm].each do |action|
        FocusSession.transaction(requires_new: true) do
          attributes = { status: status }
          attributes[:started_at] = @clock.wall unless %w[ready cancelled].include?(status)
          attributes.merge!(running_since: @clock.wall, deadline_at: @clock.wall + 1500) if status == "running"
          attributes[:paused_at] = @clock.wall if status == "paused"
          attributes[:elapsed_seconds] = 1500 if %w[awaiting_confirmation completed].include?(status)
          attributes[:completed_at] = @clock.wall if status == "completed"
          attributes[:ended_at] = @clock.wall if %w[completed cancelled].include?(status)
          session = @user.focus_sessions.create!(attributes)
          parameters = {}
          parameters[:intent] = @engine.issue if action == "restart"
          parameters.merge!(recovery_id: 1, decision: "keep_checkpoint") if action == "resolve"
          allowed = (action == "start" && status == "ready") || (action == "resume" && status == "paused") ||
            (%w[pause reconcile].include?(action) && status == "running") ||
            (%w[restart cancel].include?(action) && FocusSession::OCCUPYING.include?(status)) ||
            (action == "confirm" && status == "awaiting_confirmation")
          before = focus_rows
          if allowed
            assert focus_action(session, action, **parameters), "#{status}/#{action}"
          else
            assert_raises(FocusCommands::Conflict, "#{status}/#{action}") { focus_action(session, action, **parameters) }
            assert_equal before, focus_rows
          end
          assert_operator FocusSession.occupying.count, :<=, 1
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "start pause resume deadline and explicit completion preserve historical timestamps" do
    session = create_focus
    initial_uid = session.uid
    started = session.started_at
    @clock.advance(20.8)
    focus_action(session, "pause")
    assert_equal 20, session.elapsed_seconds
    assert_equal "paused", session.status
    @clock.advance(100)
    focus_action(session, "resume")
    assert_equal started, session.started_at
    assert_equal @clock.wall + 1480, session.deadline_at
    99.times { @clock.advance(15); @engine.read }
    assert_equal "running", session.reload.status
    assert_equal 0, FocusSession.where(status: "completed").count
    focus_action(session, "reconcile")
    assert_equal "awaiting_confirmation", session.status
    assert_nil session.running_since
    focus_action(session, "confirm")
    assert_equal "completed", session.status
    assert_equal @clock.wall, session.completed_at
    assert_equal initial_uid, session.uid
    assert_equal started, session.started_at
    assert_nil @engine.read.fetch("session")
  end

  test "unknown partial interval survives another engine process and resolution has a new receipt" do
    session = create_focus
    @clock.advance(10)
    focus_action(session, "pause")
    focus_action(session, "resume")
    @clock.advance(75)
    focus_action(session, "reconcile")
    pending = @engine.read.fetch("recovery")
    assert_equal "paused", session.status
    assert_equal 10, session.elapsed_seconds
    assert_equal 85, pending.fetch("candidate_seconds")
    historical = FocusCommand.find(pending.fetch("receipt_id")).attributes
    @clock.epoch = "restarted"
    @engine = FocusCommands.new(@user, time: FocusTime.new(clock: @clock, observations: FocusTime::Observations.new))
    assert_equal pending, @engine.read.fetch("recovery")
    assert_raises(FocusCommands::Conflict) { focus_action(session, "resume") }
    original_version = session.lock_version
    payload = { "action" => "resolve", "recovery_id" => pending.fetch("receipt_id"), "decision" => "accept_estimate" }
    options = { uid: session.uid, command_id: "resolve-after-reload", version: original_version, kind: "pause", parameters: payload }
    result = @engine.command(**options)
    assert_equal 85, session.reload.elapsed_seconds
    assert_equal original_version + 1, session.lock_version
    assert_nil @engine.read.fetch("recovery")
    assert_equal historical, FocusCommand.find(pending.fetch("receipt_id")).attributes
    assert_equal result.fetch("result"), @engine.command(**options).fetch("result")
    assert_raises(ActiveRecord::StaleObjectError) { @engine.command(**options.merge(command_id: "obsolete")) }
    assert_raises(FocusCommands::Conflict) { focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "keep_checkpoint") }
  end

  test "keeping checkpoint increments version and invalid clock cannot supply free seconds" do
    session = create_focus
    @clock.advance(60, monotonic: 1)
    focus_action(session, "pause")
    pending = @engine.read.fetch("recovery")
    assert_nil pending.fetch("candidate_seconds")
    version = session.lock_version
    assert_raises(FocusCommands::Invalid) { focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "accept_estimate") }
    assert_raises(FocusCommands::Invalid) { focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "keep_checkpoint", seconds: 1000) }
    focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "keep_checkpoint")
    assert_equal 0, session.elapsed_seconds
    assert_equal version + 1, session.lock_version
    assert_nil @engine.read.fetch("recovery")
  end

  test "closed browser deadline requires accepting unknown time and then explicit completion" do
    session = create_focus
    @clock.advance(5000)
    3.times { assert_equal "running", @engine.read.dig("session", "status") }
    assert_equal 0, session.reload.elapsed_seconds
    assert_raises(FocusCommands::Conflict) { focus_action(session, "confirm") }
    focus_action(session, "reconcile")
    pending = @engine.read.fetch("recovery")
    assert_equal "paused", session.status
    focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "accept_estimate")
    assert_equal "awaiting_confirmation", session.status
    assert_nil session.completed_at
    focus_action(session, "confirm")
    assert_equal "completed", session.status
  end

  test "response lost replay is historical and current snapshot never regresses" do
    intent = @engine.issue
    options = { intent: intent, command_id: "lost-start", version: 0, action: "start_new" }
    first = @engine.prepare(**options)
    session = FocusSession.first
    @clock.advance(10)
    focus_action(session, "pause")
    before = focus_rows
    retry_result = @engine.prepare(**options)
    assert_equal first.fetch("result"), retry_result.fetch("result")
    assert_equal "running", retry_result.dig("result", "session", "status")
    assert_equal "paused", retry_result.dig("current", "session", "status")
    assert_equal before, focus_rows
    assert_raises(FocusCommand::IncompatibleRetry) { @engine.prepare(**options.merge(action: "prepare")) }
    assert_raises(FocusCommands::Conflict) { @engine.prepare(**options.merge(intent: @engine.issue)) }
    assert_equal before, focus_rows
  end

  test "reset creates a new UID and late receipt failure rolls back old new and preference" do
    session = create_focus
    intent = @engine.issue(duration: 2700)
    before = focus_rows
    FocusCommand.connection.execute("CREATE TEMP TRIGGER synthetic_focus_failure BEFORE INSERT ON focus_commands BEGIN SELECT RAISE(ABORT, 'Synthetic late receipt failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) do
      focus_action(session, "restart", intent: intent, preference_version: @user.user_preferences_scope.first.lock_version)
    end
    assert_equal before, focus_rows
    FocusCommand.connection.execute("DROP TRIGGER synthetic_focus_failure")
    result = focus_action(session, "restart", intent: intent, preference_version: @user.user_preferences_scope.first.lock_version)
    assert_equal "cancelled", session.status
    assert_equal "reset", session.end_reason
    refute_equal session.uid, result.dig("result", "new_session_uid")
    assert_equal "ready", result.dig("current", "session", "status")
    assert_equal 2700, result.dig("current", "session", "duration_seconds")
    assert_equal 2700, @user.user_preferences_scope.first.focus_duration_seconds
    assert_equal 2, FocusSession.count
  ensure
    FocusCommand.connection.execute("DROP TRIGGER IF EXISTS synthetic_focus_failure")
  end

  test "contexts ownership completed tasks and movement keep original IDs without editing children" do
    first = project_for(@user, uid: "42/á?%#项目")
    second = project_for(@user)
    task = @user.tasks.create!(project: first, title: "Contexto QA")
    session = create_focus(context: context_for(first, task))
    task.update!(project: second)
    focus_action(session, "pause")
    focus_action(session, "resume")
    assert_equal first.id, session.project_id
    assert_equal task.id, session.task_id
    before = [ first.reload.attributes, second.reload.attributes, task.reload.attributes ]
    focus_action(session, "cancel")
    assert_equal before, [ first.reload.attributes, second.reload.attributes, task.reload.attributes ]
    task.update!(status: "completed", completed_at: Time.current)
    assert_raises(FocusCommands::Conflict) { @engine.issue(context: context_for(second, task)) }
    foreign = project_for(second_synthetic_user)
    assert_raises(ActiveRecord::RecordNotFound) { @engine.issue(context: context_for(foreign)) }
    assert_raises(FocusCommands::Conflict) { @engine.issue(context: context_for(first, task)) }
  end

  test "personal task and project without task are supported and stale context is rejected" do
    task = @user.tasks.create!(title: "Pessoal")
    intent = @engine.issue(context: context_for(nil, task))
    task.update!(title: "Mudou")
    assert_raises(FocusCommands::Conflict) { @engine.prepare(intent: intent, command_id: "stale-context", version: 0) }
    assert_equal 0, FocusSession.count
    personal = create_focus(context: context_for(nil, task))
    assert_nil personal.project_id
    assert_equal task.id, personal.task_id
    focus_action(personal, "cancel")
    project = project_for(@user)
    contextual = create_focus(context: context_for(project))
    assert_equal project.id, contextual.project_id
    assert_nil contextual.task_id
  end

  test "archived context permits reconciliation resolution completion cancellation but blocks new work" do
    project = project_for(@user)
    session = create_focus(context: context_for(project))
    project.archive!
    @clock.advance(1700)
    focus_action(session, "reconcile")
    pending = @engine.read.fetch("recovery")
    assert_raises(FocusCommands::Conflict) { focus_action(session, "resume") }
    assert_raises(FocusCommands::Conflict) { focus_action(session, "restart", intent: @engine.issue) }
    focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "accept_estimate")
    focus_action(session, "confirm")
    assert_equal "completed", session.status
    assert_equal "archived", project.reload.status
    assert_raises(FocusCommands::Conflict) { @engine.issue(context: context_for(project)) }
  end

  test "preset respects C aggregate version and does not overwrite other fields or active duration" do
    preference = @user.user_preferences_scope.first
    preference.update!(theme: "light", legacy_cookie_backup: { "source" => "synthetic" })
    original = preference.attributes.except("focus_duration_seconds", "lock_version", "updated_at")
    assert_raises(FocusCommands::Conflict) { @engine.preset(duration: 2700, version: 0) }
    @engine.preset(duration: 2700, version: preference.lock_version)
    preference.reload
    assert_equal original, preference.attributes.except("focus_duration_seconds", "lock_version", "updated_at")
    assert_equal 2700, preference.focus_duration_seconds
    session = create_focus
    assert_raises(FocusCommands::Conflict) { @engine.preset(duration: 1500, version: preference.lock_version) }
    assert_equal 2700, session.reload.duration_seconds
    assert_raises(FocusCommands::Invalid) { @engine.preset(duration: 200, version: preference.lock_version) }
  end

  test "strict commands slot and versions reject invalid inputs without side effects" do
    session = create_focus
    before = focus_rows
    assert_raises(FocusCommands::Conflict) { create_focus }
    assert_raises(FocusCommands::Conflict) { @engine.command(uid: session.uid, command_id: "no-version", version: nil, kind: "pause", parameters: { "action" => "pause" }) }
    assert_raises(FocusCommands::Invalid) { @engine.command(uid: session.uid, command_id: "wrong-kind", version: session.lock_version, kind: "resume", parameters: { "action" => "resume" }) }
    assert_raises(FocusCommands::Invalid) { @engine.command(uid: session.uid, command_id: "inject", version: session.lock_version, kind: "pause", parameters: { "action" => "pause", "elapsed_seconds" => 1500 }) }
    assert_equal before, focus_rows
  end

  test "context version types and archived ready start cannot bypass guards" do
    project = project_for(@user)
    assert_raises(FocusCommands::Conflict) { @engine.issue(context: { "project_uid" => project.uid, "project_version" => 0.0 }) }
    assert_raises(FocusCommands::Invalid) { @engine.issue(context: { "project_uid" => false }) }
    session = create_focus(action: "prepare", context: context_for(project))
    project.archive!
    before = focus_rows
    assert_raises(FocusCommands::Conflict) { focus_action(session, "start") }
    assert_equal before, focus_rows
    focus_action(session, "cancel")
    assert_equal "cancelled", session.status
    assert_nil session.started_at
  end

  test "pending recovery IDs cannot be reused after cancellation and reset retries do not duplicate history" do
    session = create_focus
    @clock.advance(80)
    focus_action(session, "reconcile")
    pending = @engine.read.fetch("recovery")
    options = { uid: session.uid, command_id: "stable-reset", version: session.lock_version, kind: "reset",
      parameters: { "action" => "restart", "intent" => @engine.issue } }
    first = @engine.command(**options)
    before = focus_rows
    assert_equal first.fetch("result"), @engine.command(**options).fetch("result")
    assert_equal before, focus_rows
    assert_raises(FocusCommands::Conflict) { focus_action(session, "resolve", recovery_id: pending.fetch("receipt_id"), decision: "keep_checkpoint") }
    assert_equal before, focus_rows
  end
end
