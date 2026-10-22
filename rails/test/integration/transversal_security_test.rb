require "test_helper"
require_relative "../support/relational_helpers"

# F2b investigation only: real cookie authentication and explicitly enabled CSRF.
class TransversalSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @prior_csrf = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @user, @password = synthetic_admin
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
    @project = @user.projects.create!(uid: "42/á?%#项目", name: "Synthetic private project")
    @task = @user.tasks.create!(uid: "1/旧", title: "Synthetic private task", project: @project)
    @reference = @user.project_references.create!(uid: "ref/α", project: @project, title: "Synthetic private reference", kind: "material")
    get new_session_path, headers: local_headers
    @csrf = css_select("meta[name=csrf-token]").first["content"]
    post session_path, params: { email_address: @user.email_address, password: @password }, headers: valid_headers
    assert_redirected_to root_path
    refresh_csrf
    assert ActionController::Base.allow_forgery_protection
    assert AuthSession.active.exists?
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @prior_csrf
  end

  def refresh_csrf
    get root_path, headers: local_headers
    assert_response :success
    @csrf = css_select("meta[name=csrf-token]").first["content"]
    assert @csrf.present?
  end

  def valid_headers
    local_headers.merge("X-CSRF-Token" => @csrf)
  end

  def domain
    [ Project, Task, ProjectReference, UserPreference, DockShortcut, WidgetPlacement, FocusSession, FocusCommand ].map { |model| model.order(:id).map(&:attributes) }
  end

  test "real authenticated writes reject missing wrong and cross-origin CSRF without mutation" do
    requests = [
      [ :post, appearance_bootstrap_path, {} ],
      [ :patch, appearance_path, { version: 0, appearance: Studio.defaults } ],
      [ :post, projects_path, { intent: ProjectCommands.new(@user).issue, project: { name: "CSRF attack" } } ],
      [ :patch, project_path(@project), { version: 0, project: { name: "CSRF edit" } } ],
      [ :patch, command_project_path(@project), { version: 0, operation: "archive" } ],
      [ :patch, project_filters_path, { version: 0, filters: { project_library_status: "archived" } } ],
      [ :post, tasks_path, { intent: TaskCommands.new(@user).issue, task: { title: "CSRF" } } ],
      [ :patch, task_path(@task), { version: 0, task: { title: "CSRF" } } ],
      [ :patch, status_task_path(@task), { version: 0, status: "completed" } ],
      [ :post, project_references_path(@project), { intent: ReferenceCommands.new(@user).issue(context: @project.uid), reference: { title: "CSRF", kind: "material" } } ],
      [ :patch, project_reference_path(@project, @reference), { version: 0, reference: { title: "CSRF" } } ],
      [ :post, "/focus/intents", {} ],
      [ :post, "/focus/prepare", {} ],
      [ :post, "/focus/#{PublicUid.encode('missing')}/commands", {} ],
      [ :patch, "/focus/preset", { version: 0, duration_seconds: 2700 } ],
      [ :delete, session_path, {} ]
    ]
    before = domain
    sessions = AuthSession.order(:id).map(&:attributes)
    requests.each do |method, path, params|
      [ local_headers, local_headers.merge("X-CSRF-Token" => "wrong") ].each do |headers|
        public_send(method, path, params: params, as: :json, headers: headers)
        assert_response :unprocessable_entity, "#{method} #{path}"
        assert_equal before, domain
        assert_equal sessions, AuthSession.order(:id).map(&:attributes)
      end
    end
    post "/focus/intents", params: {}, as: :json, headers: valid_headers.merge("HTTP_ORIGIN" => "https://evil.test")
    assert_response :unprocessable_entity
    assert_equal before, domain
    patch "/focus/preset", params: { version: 0, duration_seconds: 2700 }, as: :json, headers: valid_headers
    assert_response :success
    assert_equal 2700, @user.user_preferences_scope.first.focus_duration_seconds
  end

  test "expired and revoked sessions cannot read private HTML or JSON" do
    AuthSession.update_all(expires_at: 1.second.ago)
    [ root_path, projects_path, tasks_path, project_path(@project), task_search_path(q: "private") ].each do |path|
      get path, headers: local_headers
      assert_redirected_to new_session_path
      assert_no_match(/Synthetic private/, response.body)
    end
    [ "/focus/state", projects_path, tasks_path ].each do |path|
      get path, as: :json, headers: local_headers
      assert_response :unauthorized
      assert_no_match(/Synthetic private|password_digest/, response.body)
    end
  end

  test "logout revokes the current session and replayed signed cookie is refused" do
    old_cookie = cookies["auth_session_id"]
    delete session_path, headers: valid_headers
    assert_equal 0, AuthSession.active.count
    cookies["auth_session_id"] = old_cookie
    get "/focus/state", as: :json, headers: local_headers
    assert_response :unauthorized
    get root_path, headers: local_headers
    assert_redirected_to new_session_path
  end

  test "foreign ownership and manipulated public UIDs cannot expose or edit records" do
    foreign = second_synthetic_user
    project = foreign.projects.create!(uid: "foreign/α", name: "FOREIGN SENTINEL")
    task = foreign.tasks.create!(uid: "foreign/任务", project: project, title: "FOREIGN SENTINEL")
    reference = foreign.project_references.create!(project: project, uid: "foreign/ref", title: "FOREIGN SENTINEL", kind: "material")
    before = domain
    [ project_path(project), edit_project_path(project), edit_task_path(task), edit_project_reference_path(project, reference) ].each do |path|
      get path, as: :json, headers: local_headers
      assert_response :not_found
      assert_no_match(/FOREIGN SENTINEL|password_digest|SQLite3|SELECT /, response.body)
    end
    patch task_path(task), params: { version: 0, task: { title: "intrusion" } }, as: :json, headers: valid_headers
    assert_response :not_found
    patch project_reference_path(@project, reference), params: { version: 0, reference: { title: "intrusion" } }, as: :json, headers: valid_headers
    assert_response :not_found
    post "/focus/intents", params: { context: { project_uid: project.to_param } }, as: :json, headers: valid_headers
    assert_response :not_found
    [ "bad", "u-!", PublicUid.encode("missing/项目"), "u-AA" ].each do |uid|
      get "/projects/#{uid}", as: :json, headers: local_headers
      assert_response :not_found
      assert_no_match(/FOREIGN SENTINEL|SQLite3|SELECT /, response.body)
    end
    assert_equal before, domain
    assert_equal @project.uid, PublicUid.decode(@project.to_param)
    get project_path(@project), headers: local_headers
    assert_response :success
    assert_no_match(/FOREIGN SENTINEL/, response.body)
  end

  test "forged foreign and cross-operation creation intentions fail without mutation" do
    other = second_synthetic_user
    tokens = [ "forged", ProjectCommands.new(other).issue, TaskCommands.new(@user).issue ]
    before = domain
    tokens.each do |token|
      post projects_path, params: { intent: token, project: { name: "Attack" } }, as: :json, headers: valid_headers
      assert_response :unprocessable_entity
    end
    post tasks_path, params: { intent: ProjectCommands.new(@user).issue, task: { title: "Attack" } }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    post project_references_path(@project), params: { intent: TaskCommands.new(@user).issue(context: @project.uid), reference: { title: "Attack", kind: "material" } }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    assert_equal before, domain
  end

  test "signed intention tampering and incompatible retries do not duplicate effects" do
    intent = ReferenceCommands.new(@user).issue(context: @project.uid)
    body = { intent: intent, reference: { title: "Original", kind: "material" } }
    post project_references_path(@project), params: body, as: :json, headers: valid_headers
    assert_response :success
    before = domain
    post project_references_path(@project), params: body, as: :json, headers: valid_headers
    assert_response :success
    assert_equal before, domain
    post project_references_path(@project), params: body.deep_merge(reference: { title: "Changed" }), as: :json, headers: valid_headers
    assert_response :conflict
    post project_references_path(@project), params: body.merge(intent: intent.sub(/\A./, intent.start_with?("a") ? "b" : "a")), as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    assert_equal before, domain
  end

  test "strong parameters preserve identity and reject missing stale versions" do
    patch task_path(@task), params: { version: 0, task: { title: "Allowed edit", uid: "evil", user_id: 2, completed_at: Time.current, lock_version: 99, project_id: 999 } }, as: :json, headers: valid_headers
    assert_response :success
    assert_equal [ "1/旧", @user.id, @project.id, nil, 1 ], @task.reload.attributes.values_at("uid", "user_id", "project_id", "completed_at", "lock_version")
    before = domain
    [ nil, 0, -1, "bad" ].each do |version|
      patch task_path(@task), params: { version: version, task: { title: "Stale" } }, as: :json, headers: valid_headers
      assert_response :conflict
    end
    post "/focus/intents", params: { user_id: 2 }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    patch "/focus/preset", params: { duration_seconds: 2700 }, as: :json, headers: valid_headers
    assert_response :conflict
    assert_equal before, domain
  end

  test "private responses are not cached and maintenance routes are absent" do
    [ root_path, projects_path, tasks_path, project_path(@project), "/focus/state", task_search_path(q: "private") ].each do |path|
      get path, headers: local_headers
      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
    end
    %w[/admin/reset /admin/create /maintenance /backup /password/reset].each do |path|
      %w[GET POST PATCH DELETE].each do |method|
        assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(path, method: method) }
      end
    end
  end
  test "unauthenticated JSON requests with a real CSRF session are unauthorized" do
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! "localhost"
    client.get new_session_path, headers: local_headers
    token = Nokogiri::HTML(client.response.body).at_css("meta[name=csrf-token]")["content"]
    headers = local_headers.merge("X-CSRF-Token" => token)
    before = domain
    [ [ :get, "/focus/state", {} ], [ :get, projects_path, {} ],
      [ :patch, "/focus/preset", { duration_seconds: 2700, version: 0 } ],
      [ :post, projects_path, { project: { name: "Anonymous" } } ],
      [ :post, tasks_path, { task: { title: "Anonymous" } } ],
      [ :post, project_references_path(@project), { reference: { title: "Anonymous" } } ] ].each do |method, path, body|
      client.public_send(method, path, params: body, as: :json, headers: headers.dup)
      assert_equal 401, client.response.status, "#{method} #{path}: #{client.response.body[0, 160]}"
      assert_no_match(/Synthetic private|password_digest/, client.response.body)
    end
    assert_equal before, domain
  end

  test "focus intentions receipts and strict envelopes resist cross-domain reuse" do
    other = second_synthetic_user
    AppearancePreferences.new(other).bootstrap(legacy: nil, raw: nil)
    before = domain
    [ "forged", ProjectCommands.new(@user).issue, FocusCommands.new(other).issue ].each do |intent|
      post "/focus/prepare", params: { intent: intent, command_id: SecureRandom.uuid, version: 0, operation: "prepare" }, as: :json, headers: valid_headers
      assert_response :unprocessable_entity
    end
    assert_equal before, domain
    post "/focus/intents", params: {}, as: :json, headers: valid_headers
    assert_response :success
    body = { intent: response.parsed_body.fetch("intent"), command_id: "f2b-ready", version: 0, operation: "prepare" }
    post "/focus/prepare", params: body, as: :json, headers: valid_headers
    assert_response :success
    uid = PublicUid.encode(response.parsed_body.dig("current", "session", "uid"))
    before = domain
    post "/focus/prepare", params: body, as: :json, headers: valid_headers
    assert_response :success
    assert response.parsed_body.fetch("replayed")
    assert_equal before, domain
    post "/focus/prepare", params: body.merge(operation: "start_new"), as: :json, headers: valid_headers
    assert_response :conflict
    post "/focus/#{uid}/commands", params: { command_id: "f2b-ready", version: 0, kind: "reset", parameters: { action: "cancel" } }, as: :json, headers: valid_headers
    assert_response :conflict
    post "/focus/#{uid}/commands", params: { command_id: "f2b-extra", version: 0, kind: "start", parameters: { action: "start", elapsed_seconds: 1500 } }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    post "/focus/#{uid}/commands", params: { command_id: "f2b-context", version: 0, kind: "start", parameters: { action: "start" }, user_id: 2 }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    assert_equal before, domain
    assert_equal 1, FocusSession.occupying.count
  end

  test "malformed structured payloads receive defined failures without internal error leakage" do
    before = domain
    requests = [
      [ :patch, project_path(@project), { version: 0, project: { name: [] } }, 200 ],
      [ :patch, task_path(@task), { version: {}, task: { title: "Bad" } }, 409 ],
      [ :patch, project_reference_path(@project, @reference), { version: 0, reference: { url: [] } }, 422 ],
      [ :post, "/focus/intents", { context: [] }, 422 ],
      [ :post, "/focus/#{PublicUid.encode('missing')}/commands", { command_id: "bad", version: 0, kind: "start", parameters: [] }, 422 ]
    ]
    requests.each do |method, path, params, status|
      public_send(method, path, params: params, as: :json, headers: valid_headers)
      assert_response status
      assert_no_match(/SQLite3|SELECT |password_digest|backtrace/, response.body)
      assert_equal before, domain
    end
  end

  # F2B-01 regression: preserve the controlled public rejection contract.
  test "object project intention should be rejected as invalid input" do
    before = domain
    post projects_path, params: { intent: { forged: true }, project: { name: "Bad" } }, as: :json, headers: valid_headers
    assert_response :unprocessable_entity
    assert_equal before, domain
  end
  test "malformed project intention matrix is rejected without writes or internal details" do
    other = second_synthetic_user
    valid = ProjectCommands.new(@user).issue
    invalid_signature = valid.sub(/.$/, valid.end_with?("a") ? "b" : "a")
    values = [ { forged: true }, [ "forged" ], 42, true, false, nil, "", "malformed", invalid_signature,
      TaskCommands.new(@user).issue, ProjectCommands.new(other).issue ]
    before = domain
    values.each do |intent|
      post projects_path, params: { intent: intent, project: { name: "Never saved" } }, as: :json, headers: valid_headers
      assert_response :unprocessable_entity, intent.class.name
      assert_equal "invalid_project", response.parsed_body.fetch("error")
      assert_match(/Intenção inválida/, response.parsed_body.fetch("message"))
      assert_no_match(/NoMethodError|valid_encoding|backtrace|app\/|SQLite3|password_digest/, response.body)
      assert_equal before, domain
      assert_equal 1, Project.count
    end
  end

  test "valid project intention with enabled CSRF commits replays and rejects divergent retry" do
    intent = ProjectCommands.new(@user).issue
    body = { intent: intent, project: { name: "Legitimate intent", description: "Synthetic", icon: "grid", color: "#8befcc" } }
    post projects_path, params: body, as: :json, headers: valid_headers
    assert_response :success
    project = @user.projects.find_by!(name: "Legitimate intent")
    assert_equal @user.id, project.user_id
    assert_equal 2, Project.count
    before = domain
    post projects_path, params: body, as: :json, headers: valid_headers
    assert_response :success
    assert_equal before, domain
    assert_equal project.uid, @user.projects.find_by!(name: "Legitimate intent").uid
    post projects_path, params: body.deep_merge(project: { name: "Divergent retry" }), as: :json, headers: valid_headers
    assert_response :conflict
    assert_equal before, domain
  end
end
