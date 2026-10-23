require "test_helper"

class TransversalIdentityTest < ActiveSupport::TestCase
  test "every public UID owner and immutable receipt survives direct SQL tampering" do
    user = synthetic_admin.first
    project = user.projects.create!(uid: "legacy/项目", name: "Identity QA")
    task = user.tasks.create!(project: project, uid: "42", title: "Identity QA")
    reference = user.project_references.create!(project: project, uid: "ref/α", title: "Identity QA", kind: "material")
    session = user.focus_sessions.create!(uid: "focus/旧", project: project, task: task)
    [ project, task, reference, session ].each do |record|
      before = record.attributes
      [ { uid: "replacement" }, { user_id: 2 } ].each do |attributes|
        assert_raises(ActiveRecord::StatementInvalid) { record.class.where(id: record.id).update_all(attributes) }
        assert_equal before, record.reload.attributes
      end
    end
    receipt = FocusCommand.record!(user: user, command_id: "f2b-immutable", kind: "reset", focus_session: session, expected_version: 0) do |target|
      target.update!(duration_seconds: 2700)
      { "duration" => 2700 }
    end
    before = receipt.attributes
    [ { command_id: "changed" }, { kind: "start" }, { expected_lock_version: 99 }, { request_digest: "b" * 64 },
      { parameters: { "injected" => true } }, { result: {} } ].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) { FocusCommand.where(id: receipt.id).update_all(attributes) }
      assert_equal before, receipt.reload.attributes
    end
    assert_raises(ActiveRecord::StatementInvalid) { FocusCommand.where(id: receipt.id).delete_all }
    assert_equal before, receipt.reload.attributes
    assert_equal 1, FocusSession.occupying.count
    assert_empty User.connection.select_all("PRAGMA foreign_key_check").to_a
    assert_equal "ok", User.connection.select_value("PRAGMA integrity_check")
    assert_equal 25, User.connection.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger'")
  end
end
