require "test_helper"
require_relative "../support/relational_helpers"

class RelationalDomainTest < ActiveSupport::TestCase
  test "opaque and numeric legacy UIDs round trip safely and survive rename" do
    [ "1", "ID / especial", "a.b#?", "ação 😀", " Identificador " ].each do |uid|
      project = project_for(uid: uid)
      assert_match(/\Au-[A-Za-z0-9_-]+\z/, project.to_param)
      assert_equal uid, PublicUid.decode(project.to_param)
      project.update!(name: "Renomeado #{project.id}")
      assert_equal uid, project.reload.uid
    end
    assert_equal "7", project_for(uid: 7).uid
    [ "", "u-", "u-Zg=", "u-A", "u-AA", "u-_w", "../x", "u-Zg/" ].each do |token|
      assert_raises(ArgumentError) { PublicUid.decode(token) }
    end
    assert_raises(ArgumentError) { PublicUid.encode("\0") }
  end

  test "identities are unique per owner and entity and immutable" do
    project = project_for(uid: "legacy")
    assert_not relational_user.projects.new(uid: project.uid, name: "Outro").valid?
    task = relational_user.tasks.create!(uid: project.uid, title: "Identidade em outra entidade")
    assert_not relational_user.tasks.new(uid: task.uid, title: "Duplicada").valid?
    assert_raises(ActiveRecord::ReadonlyAttributeError) { project.update!(uid: "replacement") }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { task.update!(user_id: 2) }
  end

  test "project names normalize consistently including archived duplicates" do
    project = project_for(name: "  Projeto   Ａ  ")
    assert_equal "projeto a", project.name_key
    project.archive!
    assert_not relational_user.projects.new(name: "PROJETO A").valid?
    assert relational_user.projects.new(name: "Projeto Á").valid?
  end

  test "archive and restore preserve records and block global edits and deletion" do
    project = project_for(status: "paused")
    task = relational_user.tasks.create!(project: project, title: "Preservada")
    reference = relational_user.project_references.create!(project: project, title: "Livro", kind: "material")
    widget = relational_user.widget_placements.create!(project: project, context: "project", widget_key: "tasks", position: 0, span: 5)
    original = [ task, reference, widget ].map(&:attributes)
    project.archive!
    version = project.lock_version
    project.archive!
    assert_equal version, project.lock_version
    assert_equal "paused", project.archived_from
    assert_raises(ActiveRecord::RecordInvalid) { task.update!(status: "completed") }
    assert_raises(ActiveRecord::RecordInvalid) { reference.update!(title: "Alterado") }
    assert_raises(ActiveRecord::RecordInvalid) { widget.update!(span: 8) }
    assert_raises(ActiveRecord::RecordInvalid) { project.update!(favorite: true) }
    assert_not task.destroy
    assert_not reference.destroy
    assert_not project.destroy
    assert_equal original, [ task, reference, widget ].map { |r| r.reload.attributes }
    project.reload.restore!
    assert_equal "paused", project.status
    assert_nil project.archived_from
    version = project.lock_version
    project.restore!
    assert_equal version, project.lock_version
    task.update!(status: "completed")
    assert_equal "completed", task.reload.status
  end

  test "moving a record cannot evade protection of its old archived project" do
    archived = project_for
    destination = project_for
    task = relational_user.tasks.create!(project: archived, title: "Origem")
    archived.archive!
    assert_raises(ActiveRecord::RecordInvalid) { task.update!(project: destination) }
    assert_equal archived.id, task.reload.project_id
  end

  test "all editable records reject stale versions" do
    project = project_for
    records = [
      [ project, { description: "Primeira" }, { description: "Segunda" } ],
      [ relational_user.tasks.create!(title: "Tarefa"), { title: "Primeira" }, { title: "Segunda" } ],
      [ relational_user.project_references.create!(project: project, title: "Material", kind: "material"), { title: "Primeira" }, { title: "Segunda" } ],
      [ relational_user.create_user_preference!, { theme: "light" }, { wallpaper: "ocean" } ],
      [ relational_user.dock_shortcuts.create!(module_key: "tasks", position: 0), { visible: false }, { visible: false } ],
      [ relational_user.widget_placements.create!(widget_key: "tasks", position: 0, span: 5), { span: 8 }, { span: 12 } ],
      [ prepared_focus, { duration_seconds: 2700 }, { duration_seconds: 2700 } ]
    ]
    records.each do |record, first, second|
      copy = record.class.find(record.id)
      record.update!(first)
      assert_raises(ActiveRecord::StaleObjectError) { copy.update!(second) }
      assert_equal first.values, record.reload.attributes.values_at(*first.keys.map(&:to_s))
    end
  end

  test "model validations reject cross owner relations" do
    project = project_for
    other = second_synthetic_user
    other_project = project_for(other)
    other_task = other.tasks.create!(project: other_project, title: "Outro")
    assert_not relational_user.tasks.new(project: other_project, title: "Invasão").valid?
    assert_not relational_user.project_references.new(project: other_project, title: "Invasão", kind: "material").valid?
    assert_not relational_user.widget_placements.new(project: other_project, context: "project", widget_key: "tasks", position: 0, span: 5).valid?
    assert_not relational_user.focus_sessions.new(project: other_project).valid?
    assert_not relational_user.focus_sessions.new(task: other_task, project: project).valid?
    other_focus = prepared_focus(other)
    command = relational_user.focus_commands.new(focus_session: other_focus, command_id: "x", kind: "start", expected_lock_version: 0, request_digest: "a" * 64, parameters: {}, result: {})
    assert_not command.valid?
  end

  test "reference URLs and field limits reject invalid content" do
    project = project_for
    %w[javascript:alert(1) data:text/html,test file:///tmp/test https://user:password@example.test https:///missing].each do |url|
      assert_not relational_user.project_references.new(project: project, title: "Link", url: url).valid?
    end
    assert relational_user.project_references.new(project: project, title: "Link", url: "https://example.test/path@name?q=1").valid?
    assert relational_user.project_references.new(project: project, title: "Livro", kind: "material").valid?
    assert_not relational_user.tasks.new(title: "a" * 121).valid?
    assert_not relational_user.projects.new(name: "a" * 81).valid?
    assert_not relational_user.project_references.new(project: project, title: "Livro", kind: "material", description: "a" * 2001).valid?
  end
end
