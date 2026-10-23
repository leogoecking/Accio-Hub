require "test_helper"

class ProjectsTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
    @commands = ProjectCommands.new(@user)
    @attributes = { name: "Projeto QA", description: "Uma descrição", icon: "book", color: "#af9cf8" }
  end

  test "signed creation survives a lost response and rejects incompatible retries" do
    intent = @commands.issue
    assert_difference("Project.count", 1) do
      post projects_path, params: { intent: intent, project: @attributes }, as: :json, headers: local_headers
      assert_response :success
    end
    original = Project.first.attributes
    2.times do
      assert_no_difference("Project.count") { post projects_path, params: { intent: intent, project: @attributes }, as: :json, headers: local_headers }
      assert_response :success
      assert_equal original, Project.first.attributes
    end
    post projects_path, params: { intent: intent, project: @attributes.merge(name: "Outro") }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal original, Project.first.attributes
    post projects_path, params: { intent: "tampered", project: @attributes }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
  end

  test "creation validates names equivalent uniqueness fields and ignores internal parameters" do
    intent = @commands.issue
    post projects_path, params: { intent: intent, project: @attributes.merge(uid: "attacker", user_id: 999, status: "archived", archived_from: "paused") }, as: :json, headers: local_headers
    assert_response :success
    project = Project.first
    assert_not_equal "attacker", project.uid
    assert_equal @user.id, project.user_id
    assert_equal "active", project.status
    post projects_path, params: { intent: @commands.issue, project: @attributes.merge(name: "  PROJETO   QA  ") }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 1, Project.count
    post projects_path, params: { intent: @commands.issue, project: @attributes.merge(name: "", color: "javascript:alert(1)", icon: "bad") }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 1, Project.count
  end

  test "legacy unicode special routes rename without replacing uid ownership or origin dates" do
    %w[1 á/项目?%#].each do |uid|
      project = @user.projects.create!(name: uid, uid: uid, origin_created_at: 2.years.ago, origin_updated_at: 1.year.ago)
      original = project.attributes.slice("uid", "user_id", "origin_created_at", "origin_updated_at", "tint", "color")
      get project_path(project), headers: local_headers
      assert_response :success
      assert_select "#space-title", text: /#{Regexp.escape(uid)}/
      patch project_path(project), params: { version: project.lock_version, project: { name: "Renomeado #{uid}", uid: "bad", user_id: 999 } }, as: :json, headers: local_headers
      assert_response :success
      assert_equal original, project.reload.attributes.slice(*original.keys)
    end
    get "/projects/u-invalid=", headers: local_headers
    assert_response :not_found
  end

  test "versions protect edits desired favorite state status and archives preserve children" do
    project = @user.projects.create!(name: "Projeto com vínculos", status: "paused")
    task = @user.tasks.create!(project: project, title: "Tarefa QA")
    reference = @user.project_references.create!(project: project, title: "Material QA", kind: "material")
    originals = [ task.attributes, reference.attributes ]
    patch project_path(project), params: { version: 0, project: @attributes }, as: :json, headers: local_headers
    assert_response :success
    patch project_path(project), params: { version: 0, project: { name: "Sobrescrita" } }, as: :json, headers: local_headers
    assert_response :conflict
    patch command_project_path(project), params: { version: project.reload.lock_version, operation: "favorite", favorite: true }, as: :json, headers: local_headers
    assert_response :success
    assert project.reload.favorite
    patch command_project_path(project), params: { version: project.lock_version, operation: "archive" }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "paused", project.reload.archived_from
    %w[edit favorite status archive].each do |operation|
      if operation == "edit"
        patch project_path(project), params: { version: project.lock_version, project: { name: "Bloqueado" } }, as: :json, headers: local_headers
      else
        patch command_project_path(project), params: { version: project.lock_version, operation: operation, favorite: false, status: "active" }, as: :json, headers: local_headers
      end
      assert_response :conflict
    end
    patch command_project_path(project), params: { version: project.lock_version, operation: "restore" }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "paused", project.reload.status
    assert_nil project.archived_from
    assert_nil project.archived_at
    assert_equal originals, [ task.reload.attributes, reference.reload.attributes ]
  end

  test "filters persist and appearance uses the same aggregate version without overwrites" do
    original = AppearancePreferences.new(@user).read[:appearance]
    patch project_filters_path, params: { version: 0, filters: { project_library_status: "paused", project_library_sort: "recent", project_library_favorites_only: true } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal original, AppearancePreferences.new(@user).read[:appearance]
    patch "/appearance", params: { version: 0, appearance: original.merge("theme" => "light") }, as: :json, headers: local_headers
    assert_response :conflict
    patch "/appearance", params: { version: 1, appearance: original.merge("theme" => "light") }, as: :json, headers: local_headers
    assert_response :success
    patch project_filters_path, params: { version: 1, filters: { project_library_status: "all" } }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "paused", @user.user_preferences_scope.first.project_library_status
    assert_equal "light", AppearancePreferences.new(@user).read[:appearance]["theme"]
  end

  test "query accent search natural ordering filters and dashboard share actual records" do
    @user.projects.create!(name: "Projeto 10", description: "Café")
    active = @user.projects.create!(name: "Projeto 2", description: "<script>alert(1)</script>", favorite: true)
    @user.projects.create!(name: "Arquivado QA", status: "archived", archived_from: "paused", archived_at: Time.current)
    assert_equal [ "Arquivado QA", "Projeto 2", "Projeto 10" ], ProjectLibrary.new(@user).select.map(&:name)
    assert_equal [ "Projeto 10" ], ProjectLibrary.new(@user).select(search: "CAFE").map(&:name)
    get projects_path, headers: local_headers
    assert_response :success
    assert_select ".project-card", count: 3
    assert_select ".project-card script", count: 0
    get root_path, headers: local_headers
    assert_select ".project-strip .mini-project", count: 2
    assert_select ".project-strip", text: /Projeto 2/
    assert_select ".project-strip", text: /AccioCAD/, count: 0
    get project_path(active, tab: "knowledge"), headers: local_headers
    assert_select "#space-content", text: /Vault Markdown.*P1.3/
    assert_select "#space-content .space-note", count: 0
  end

  test "rollbacks and invalid filters preserve complete aggregate" do
    original = @user.user_preferences_scope.first.attributes
    patch project_filters_path, params: { version: 0, filters: { project_library_status: "bad", project_library_sort: "recent" } }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal original, @user.user_preferences_scope.first.attributes
    project = @user.projects.create!(name: "Rollback QA")
    original_project = project.attributes
    assert_raises(ActiveRecord::RecordInvalid) { @commands.change(project.uid, version: 0, operation: "edit", attributes: { name: "Novo nome", icon: "invalid" }) }
    assert_equal original_project, project.reload.attributes
  end

  test "project writes require authentication and csrf and not a signed token alone" do
    intent = @commands.issue
    delete session_path, headers: local_headers
    post projects_path, params: { intent: intent, project: @attributes }, as: :json, headers: local_headers
    assert_response :unauthorized
    assert_equal 0, Project.count
  end
  test "project actions reject foreign owners and signed claims for another operation" do
    other = second_synthetic_user
    project = other.projects.create!(name: "Projeto alheio")
    get project_path(project), headers: local_headers
    assert_response :not_found
    patch project_path(project), params: { version: 0, project: { name: "Invasão" } }, as: :json, headers: local_headers
    assert_response :not_found
    assert_equal "Projeto alheio", project.reload.name
    [ ProjectCommands.new(other).issue, Rails.application.message_verifier("project-intention").generate({ "user_id" => @user.id, "operation" => "task.create", "uid" => "fake" }, purpose: "project-create") ].each do |intent|
      post projects_path, params: { intent: intent, project: @attributes }, as: :json, headers: local_headers
      assert_response :unprocessable_entity
    end
    assert_equal 1, Project.count
  end

  test "signed project intention does not bypass csrf" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post projects_path, params: { intent: @commands.issue, project: @attributes }, as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://untrusted.example")
    assert_response :unprocessable_entity
    assert_equal 0, Project.count
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "SQL failure rolls back all changed project attributes" do
    project = @user.projects.create!(name: "Rollback SQL")
    original = project.attributes
    connection = Project.connection
    connection.execute("CREATE TEMP TRIGGER qa_reject_update BEFORE UPDATE ON projects BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) { @commands.change(project.uid, version: 0, operation: "edit", attributes: { name: "Renomeado", description: "Novo" }) }
    assert_equal original, project.reload.attributes
  ensure
    connection&.execute("DROP TRIGGER IF EXISTS qa_reject_update")
  end
  test "unexpected structured fields return validation error without writing" do
    post projects_path, params: { intent: @commands.issue, project: @attributes.merge(color: 42) }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 0, Project.count
  end
  test "stale edit links return an accessible frame for archived or missing projects" do
    project = @user.projects.create!(name: "Arquivo entre abas")
    project.archive!
    get edit_project_path(project), headers: local_headers.merge("Turbo-Frame" => "project-modal")
    assert_response :conflict
    assert_select "turbo-frame#project-modal dialog[aria-labelledby=project-unavailable-title]", count: 1
    assert_select "#project-unavailable-message", text: /somente leitura/
    assert_select "form", count: 0
    get edit_project_path(uid: PublicUid.encode("missing")), headers: local_headers.merge("Turbo-Frame" => "project-modal")
    assert_response :not_found
    assert_select "turbo-frame#project-modal dialog", count: 1
  end
  test "direct form addresses keep the library shell instead of an empty page on cancel" do
    get new_project_path, headers: local_headers
    assert_redirected_to projects_path(dialog: "new")
    follow_redirect!
    assert_select "main .project-library", count: 1
    assert_select "turbo-frame#project-modal[src=?]", new_project_path
    project = @user.projects.create!(name: "Direto QA")
    get edit_project_path(project), headers: local_headers
    assert_redirected_to projects_path(dialog: project.to_param)
    follow_redirect!
    assert_select "turbo-frame#project-modal[src=?]", edit_project_path(project)
  end
  test "favoriting never invents activity or promotes an unknown legacy activity date" do
    old = @user.projects.create!(name: "Antigo QA", created_at: 2.days.ago, updated_at: 2.days.ago)
    recent = @user.projects.create!(name: "Recent QA", last_activity_at: Time.current)
    ProjectLibrary.new(@user).update_filters({ "project_library_sort" => "recent" }, version: 0)
    @commands.change(old.uid, version: 0, operation: "favorite", attributes: { "favorite" => true })
    assert_nil old.reload.last_activity_at
    assert_equal [ recent.uid, old.uid ], ProjectLibrary.new(@user).select.map(&:uid)
    get projects_path, headers: local_headers
    assert_select ".project-activity", text: "Sem atividade registrada", count: 1
  end
end
