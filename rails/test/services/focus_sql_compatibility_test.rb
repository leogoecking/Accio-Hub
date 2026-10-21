require "test_helper"
require_relative "../support/relational_helpers"

class FocusSqlCompatibilityTest < ActiveSupport::TestCase
  test "archived lifecycle matrix agrees in ActiveRecord and SQL without changing triggers" do
    user = relational_user
    project = project_for(user)
    trigger_sql = Project.connection.select_values("SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
    assert_equal 25, trigger_sql.size
    %w[ready running paused awaiting_confirmation].each do |origin|
      %w[running paused awaiting_confirmation completed cancelled].each do |target|
        [ false, true ].each do |sql|
          FocusSession.transaction(requires_new: true) do
            now = Time.current
            attrs = { status: origin, project: project }
            attrs[:started_at] = now unless origin == "ready"
            attrs.merge!(running_since: now, deadline_at: now + 1500) if origin == "running"
            attrs[:paused_at] = now if origin == "paused"
            attrs[:elapsed_seconds] = 1500 if origin == "awaiting_confirmation"
            session = user.focus_sessions.create!(attrs)
            project.reload.archive!
            changes = { status: target, running_since: nil, deadline_at: nil, paused_at: nil,
              completed_at: nil, ended_at: nil, end_reason: nil }
            changes[:started_at] = now if origin == "ready" && target != "cancelled"
            changes.merge!(running_since: now + 1, deadline_at: now + 1501) if target == "running"
            changes[:paused_at] = now if target == "paused"
            changes[:elapsed_seconds] = 1500 if %w[awaiting_confirmation completed].include?(target)
            changes.merge!(completed_at: now, ended_at: now) if target == "completed"
            changes.merge!(ended_at: now, end_reason: "cancelled") if target == "cancelled"
            # Full awaiting sessions have no remaining segment to resume.
            allowed = target == "cancelled" || (origin != "ready" && (target != "running" || origin == "running"))
            operation = -> { sql ? FocusSession.where(id: session.id).update_all(changes) : session.update!(changes) }
            if allowed
              assert operation.call, "#{origin} -> #{target}, SQL=#{sql}"
            else
              assert_raises(sql ? ActiveRecord::StatementInvalid : ActiveRecord::RecordInvalid, "#{origin} -> #{target}, SQL=#{sql}", &operation)
            end
            assert_equal "archived", project.reload.status
            raise ActiveRecord::Rollback
          end
          project.reload
        end
      end
    end
    assert_equal trigger_sql, Project.connection.select_values("SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
    assert_empty Project.connection.select_all("PRAGMA foreign_key_check")
  end
end
