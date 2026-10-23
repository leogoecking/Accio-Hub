require "test_helper"

class TasksTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
    @commands = TaskCommands.new(@user)
    @project = @user.projects.create!(name: "Origem QA", uid: "42/á?%#项目")
    @target = @user.projects.create!(name: "Destino QA")
    @fields = { title: "Tarefa café QA", priority: "high" }
  end

  def create_task(project = nil)
    @commands.create(@commands.issue, @fields, destination: project&.uid)
  end

  test "personal and contextual creation share stable records across surfaces and ignore internal fields" do
    post tasks_path, params: { intent: @commands.issue, task: @fields.merge(uid: "bad", user_id: 99, project_id: @project.id, status: "completed", completed_at: Time.current, position: 99) }, as: :json, headers: local_headers
    assert_response :success
    personal = @user.tasks.first
    assert_nil personal.project_id
    assert_nil personal.completed_at
    assert_equal "pending", personal.status
    assert_not_equal "bad", personal.uid
    assert_equal @user.id, personal.user_id
    post project_tasks_path(@project), params: { intent: @commands.issue(context: @project.uid), task: @fields.merge(project_uid: @target.to_param) }, as: :json, headers: local_headers
    assert_response :success
    contextual = @user.tasks.order(:id).last
    assert_equal @project.id, contextual.project_id
    assert @project.reload.last_activity_at
    [ tasks_path, root_path, project_path(@project, tab: "tasks") ].each do |path|
      get path, headers: local_headers
      assert_response :success
      assert_select "[data-task-uid=?]", contextual.to_param, count: 1
    end
    get tasks_path, headers: local_headers
    assert_select ".task-list", count: 1
    assert_select ".tasks-in-card", count: 0
    get project_path(@project, tab: "tasks"), headers: local_headers
    assert_select ".task-list", count: 1
    assert_select ".tasks-in-card", count: 0
    assert_select "[data-task-uid=?]", personal.to_param, count: 0
    assert_equal 2, Task.count
    get projects_path, headers: local_headers
    assert_select ".project-card", text: /1 tarefa/, count: 1
  end

  test "equivalent signed retries do not change timestamps parent activity or duplicate records" do
    intent = @commands.issue(context: @project.uid)
    2.times do
      post project_tasks_path(@project), params: { intent: intent, task: @fields }, as: :json, headers: local_headers
      assert_response :success
      if @original
        assert_equal @original, Task.first.attributes
        assert_equal @parent, @project.reload.attributes
      end
      @original = Task.first.attributes
      @parent = @project.reload.attributes
    end
    assert_equal 1, Task.count
    post project_tasks_path(@project), params: { intent: intent, task: @fields.merge(title: "Outra") }, as: :json, headers: local_headers
    assert_response :conflict
    post tasks_path, params: { intent: intent, task: @fields }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    post tasks_path, params: { intent: "tampered", task: @fields }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal @original, Task.first.attributes
  end

  test "editing moves only globally preserves uid dates and updates both projects atomically" do
    task = create_task(@project)
    identity = task.attributes.slice("uid", "created_at", "origin_created_at", "origin_updated_at")
    before = [ @project.reload.lock_version, @target.lock_version ]
    patch task_path(task), params: { version: 0, task: @fields.merge(title: "Editada", project_uid: @target.to_param, uid: "bad", user_id: 99) }, as: :json, headers: local_headers
    assert_response :success
    assert_equal @target.id, task.reload.project_id
    assert_equal identity, task.attributes.slice(*identity.keys)
    assert_equal before.map { |v| v + 1 }, [ @project.reload.lock_version, @target.reload.lock_version ]
    patch project_task_path(@target, task), params: { version: task.lock_version, task: @fields.merge(project_uid: @project.to_param) }, as: :json, headers: local_headers
    assert_response :success
    assert_equal @target.id, task.reload.project_id
    patch task_path(task), params: { version: task.lock_version, task: @fields.merge(project_uid: "") }, as: :json, headers: local_headers
    assert_response :success
    assert_nil task.reload.project_id
  end

  test "desired completion and reopening are idempotent and server owns completion timestamps" do
    task = create_task(@project)
    patch status_task_path(task), params: { version: 0, status: "completed", completed_at: 20.years.ago }, as: :json, headers: local_headers
    assert_response :success
    assert_in_delta Time.current, task.reload.completed_at, 5
    original = task.attributes
    parent = @project.reload.attributes
    patch status_task_path(task), params: { version: task.lock_version, status: "completed" }, as: :json, headers: local_headers
    assert_response :success
    assert_equal original, task.reload.attributes
    assert_equal parent, @project.reload.attributes
    patch task_path(task), params: { version: task.lock_version, task: { title: "Novo título", priority: "normal", project_uid: @project.to_param } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal original["completed_at"], task.reload.completed_at
    patch status_project_task_path(@project, task), params: { version: task.lock_version, status: "pending" }, as: :json, headers: local_headers
    assert_response :success
    assert_nil task.reload.completed_at
    patch status_task_path(task), params: { version: 0, status: "completed" }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "pending", task.reload.status
  end

  test "archived origin and destination block edits moves and completion everywhere" do
    task = create_task(@project)
    @project.reload.archive!
    original = task.attributes
    patch task_path(task), params: { version: 0, task: @fields.merge(project_uid: @target.to_param) }, as: :json, headers: local_headers
    assert_response :conflict
    patch status_task_path(task), params: { version: 0, status: "completed" }, as: :json, headers: local_headers
    assert_response :conflict
    post project_tasks_path(@project), params: { intent: @commands.issue(context: @project.uid), task: @fields }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal original, task.reload.attributes
    get tasks_path, headers: local_headers
    assert_select "[data-task-uid=?] input[disabled]", task.to_param
    get edit_task_path(task), headers: local_headers.merge("Turbo-Frame" => "task-modal")
    assert_response :conflict
    assert_select "dialog[data-task-dialog]", count: 1
    assert_select "form", count: 0
    @project.restore!
    @target.archive!
    patch task_path(task), params: { version: 0, task: @fields.merge(project_uid: @target.to_param) }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal original, task.reload.attributes
    assert_equal "project_archived", response.parsed_body.fetch("reason")
  end

  test "ownership malformed identifiers context mismatches and authentication are enforced" do
    other = second_synthetic_user
    foreign_project = other.projects.create!(name: "Outra conta")
    foreign = other.tasks.create!(title: "Privado")
    task = create_task(@project)
    [ edit_task_path(foreign), edit_task_path(uid: "u-bad="), edit_project_task_path(@target, task) ].each do |path|
      get path, headers: local_headers
      assert_response :not_found
    end
    [ foreign_project.to_param, "u-bad=" ].each do |uid|
      post tasks_path, params: { intent: @commands.issue, task: @fields.merge(project_uid: uid) }, as: :json, headers: local_headers
      assert_response :not_found
    end
    post tasks_path, params: { intent: TaskCommands.new(other).issue, task: @fields }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    patch task_path(foreign), params: { version: 0, task: @fields }, as: :json, headers: local_headers
    assert_response :not_found
    patch status_task_path(foreign), params: { version: 0, status: "completed" }, as: :json, headers: local_headers
    assert_response :not_found
    post project_tasks_path(foreign_project), params: { intent: @commands.issue(context: foreign_project.uid), task: @fields }, as: :json, headers: local_headers
    assert_response :not_found
    assert_equal "Privado", foreign.reload.title
    get task_search_path(q: "Privado"), headers: local_headers
    assert_response :success
    assert_select "a", count: 0
    delete session_path, headers: local_headers
    post tasks_path, params: { intent: @commands.issue, task: @fields }, as: :json, headers: local_headers
    assert_response :unauthorized
  end

  test "invalid values and stale edits do not partially update tasks or projects" do
    task = create_task(@project)
    original = task.attributes
    parent = @project.reload.attributes
    [ { title: "" }, { title: "x" * 121 }, { priority: "invalid" }, { title: 42 } ].each do |bad|
      patch task_path(task), params: { version: 0, task: @fields.merge(bad).merge(project_uid: @target.to_param) }, as: :json, headers: local_headers
      assert_response :unprocessable_entity
      assert_equal original, task.reload.attributes
      assert_equal parent, @project.reload.attributes
    end
    patch task_path(task), params: { version: 0, task: @fields.merge(title: "Outra aba", project_uid: @project.to_param) }, as: :json, headers: local_headers
    assert_response :success
    patch task_path(task), params: { version: 0, task: @fields.merge(title: "Sobrescrita") }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "Outra aba", task.reload.title
    assert response.parsed_body.fetch("task").fetch("editable")
  end

  test "parent failure rolls back task movement completion and creation" do
    task = create_task(@project)
    original = task.attributes
    parents = [ @project.reload.attributes, @target.attributes ]
    connection = Task.connection
    connection.execute("CREATE TEMP TRIGGER qa_task_parent_failure BEFORE UPDATE ON projects BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) { @commands.change(task.uid, version: 0, operation: "edit", attributes: @fields, destination: @target.uid) }
    assert_raises(ActiveRecord::StatementInvalid) { @commands.change(task.uid, version: 0, operation: "status", attributes: { "status" => "completed" }) }
    assert_raises(ActiveRecord::StatementInvalid) { @commands.create(@commands.issue, @fields, destination: @project.uid) }
    assert_equal 1, Task.count
    assert_equal original, task.reload.attributes
    assert_equal parents, [ @project.reload.attributes, @target.reload.attributes ]
  ensure
    connection&.execute("DROP TRIGGER IF EXISTS qa_task_parent_failure")
  end

  test "legacy uid html escaping ordering empty states and direct forms" do
    older = @user.tasks.create!(title: "Legada", uid: "1", position: 3)
    task = @user.tasks.create!(title: "<script>alert(1)</script>", uid: "á/项目?%#", priority: "high", position: 4)
    get tasks_path, headers: local_headers
    assert_response :success
    assert_select "[data-task-uid]", count: 2
    assert_select "[data-task-uid] script", count: 0
    assert_equal [ task.to_param, older.to_param ], css_select("[data-task-uid]").map { |el| el["data-task-uid"] }
    get edit_task_path(task), headers: local_headers
    assert_redirected_to tasks_path(dialog: task.to_param)
    follow_redirect!
    assert_select "turbo-frame#task-modal[src=?]", edit_task_path(task)
    get new_project_task_path(@project), headers: local_headers
    assert_redirected_to project_path(@project, tab: "tasks", task_dialog: "new")
    get project_path(@project, tab: "tasks"), headers: local_headers
    assert_select ".space-empty", text: /Nenhuma tarefa/, count: 1
    get app_path("tasks"), headers: local_headers
    assert_redirected_to tasks_path
  end

  test "partial edit preserves priority and link while malformed destinations are rejected" do
    task = create_task(@project)
    patch task_path(task), params: { version: 0, task: { title: "Só título" } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "high", task.reload.priority
    assert_equal @project.id, task.project_id
    patch task_path(task), params: { version: task.lock_version, task: { title: "Malformada", project_uid: { uid: @target.to_param } } }, as: :json, headers: local_headers
    assert_response :not_found
    assert_equal "Só título", task.reload.title
    assert_equal @project.id, task.project_id
    post tasks_path, params: { intent: { bad: true }, task: @fields }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
  end

  test "historical metadata survives legacy uid edits and dashboard includes archived pending tasks" do
    task = @user.tasks.create!(uid: "á/项目?%#", title: "Legada", project: @project, origin_created_at: 2.years.ago, origin_updated_at: 1.year.ago)
    original = task.attributes.slice("uid", "user_id", "origin_created_at", "origin_updated_at", "created_at")
    patch task_path(task), params: { version: 0, task: @fields }, as: :json, headers: local_headers
    assert_response :success
    assert_equal original, task.reload.attributes.slice(*original.keys)
    @project.reload.archive!
    get root_path, headers: local_headers
    assert_select "#dashboard-tasks .task-stat strong", text: "01"
    assert_select "#dashboard-tasks [data-task-uid=?] input[disabled]", task.to_param, count: 1
    assert_select "#dashboard-tasks", text: /Arquivado.*somente leitura/
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(task_path(task), method: :delete) }
  end

  test "task intention is not a substitute for csrf" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post tasks_path, params: { intent: @commands.issue, task: @fields }, as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://untrusted.example")
    assert_response :unprocessable_entity
    assert_equal 0, Task.count
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
