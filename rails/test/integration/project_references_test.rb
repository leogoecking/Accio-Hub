require "test_helper"

class ProjectReferencesTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
    @project = @user.projects.create!(name: "Projeto QA", uid: "42/á?%#项目")
    @other = @user.projects.create!(name: "Outro QA")
    @commands = ReferenceCommands.new(@user)
    @fields = { title: "Site QA", kind: "link", url: "https://example.test/path?q=1#ref", description: "Consulta QA" }
  end

  def create_reference(fields = @fields)
    @commands.create(@commands.issue(context: @project.uid), fields, context: @project.uid)
  end

  test "contextual link and material creation ignore identity and internal attributes" do
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields.merge(uid: "bad", user_id: 90, project_id: @other.id, position: 99, lock_version: 30, origin_created_at: 20.years.ago) }, as: :json, headers: local_headers
    assert_response :success
    ref = @project.project_references.first
    assert_not_equal "bad", ref.uid
    assert_equal @user.id, ref.user_id
    assert_equal @project.id, ref.project_id
    assert_equal 0, ref.position
    assert_equal 0, ref.lock_version
    assert_nil ref.origin_created_at
    assert_equal 1, @project.reload.lock_version
    material = create_reference(title: "Manual", kind: "material", description: "Somente texto")
    assert_equal "", material.url
    assert_equal 1, material.position
    get project_path(@project, tab: "references"), headers: local_headers
    assert_select "[data-reference-uid]", count: 2
    assert_select "#reference-count", text: "2"
    assert_select ".space-reference a[target=_blank][rel='noopener noreferrer']", count: 1
    assert_select ".space-reference", text: /Material descrito/, count: 1
    get project_path(@project), headers: local_headers
    assert_select ".space-info dd", text: "2"
    get project_path(@other, tab: "references"), headers: local_headers
    assert_select "[data-reference-uid]", count: 0
    assert_select ".space-empty", text: /Nenhuma referência/
  end

  test "signed equivalent retry preserves reference and parent and rejects incompatible or cross-context intents" do
    intent = @commands.issue(context: @project.uid)
    2.times do
      post project_references_path(@project), params: { intent: intent, reference: @fields }, as: :json, headers: local_headers
      assert_response :success
      assert_equal @original, ProjectReference.first.attributes if @original
      assert_equal @parent, @project.reload.attributes if @parent
      @original = ProjectReference.first.attributes; @parent = @project.reload.attributes
    end
    assert_equal 1, ProjectReference.count
    post project_references_path(@project), params: { intent: intent, reference: @fields.merge(title: "Diferente") }, as: :json, headers: local_headers
    assert_response :conflict
    [ intent, "tampered", { value: intent } ].each do |token|
      post project_references_path(@other), params: { intent: token, reference: @fields }, as: :json, headers: local_headers
      assert_response :unprocessable_entity
    end
    assert_equal @original, ProjectReference.first.attributes
    assert_equal @parent, @project.reload.attributes
  end

  test "strict URL policy rejects dangerous malformed and ambiguous hosts without partial writes" do
    invalid = [ "javascript:alert(1)", "data:text/html,x", "file:///tmp/x", "/relative", "//example.test", "https://", "https://user:pass@example.test", "https://@example.test", "https://exa_mple.test", "https://.example.test", "https://example..test", "https://-example.test", "https://example.test:65536", "https://example.test/%zz", "https://example.test/\nscript", "https://example.test/\n", "\thttps://example.test", "http://127.1", "http://2130706433", "https://[::zzz]", "https://example.test\\@evil.test" ]
    parent = @project.attributes
    invalid.each do |url|
      post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields.merge(url: url) }, as: :json, headers: local_headers
      assert_response :unprocessable_entity, url
      assert_equal 0, ProjectReference.count, url
      assert_equal parent, @project.reload.attributes, url
      assert_nil SafeReferenceUrl.call(url), url
    end
    [ "http://localhost:3000", "http://127.0.0.1/a", "https://[::1]:3126/a", "HTTPS://example.test/a%20b?q=1&x=2", "https://xn--caf-dma.test", "https://example.test?email=qa@example.test#section@1" ].each do |url|
      post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields.merge(url: url) }, as: :json, headers: local_headers
      assert_response :success, url
    end
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields.merge(url: "") }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields.merge(kind: "material", url: "file:///etc/passwd") }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
  end

  test "text is escaped and incompatible stored URL cannot become an executable link" do
    ref = create_reference(@fields.merge(title: "<img src=x onerror=alert(1)>", description: "<script>alert('x')</script>"))
    # The SQL prefix CHECK permits this malformed host, simulating a legacy record.
    ref.update_columns(url: "https://bad_host.test")
    get project_path(@project, tab: "references"), headers: local_headers
    assert_response :success
    assert_select ".space-reference img, .space-reference script", count: 0
    assert_select ".space-reference h3", text: ref.title
    assert_select ".space-reference a[target=_blank]", count: 0
    assert_select ".space-reference", text: /link desativado por segurança/
    assert_includes response.body, "&lt;script&gt;"
    assert_equal "https://bad_host.test", ref.reload.url
  end

  test "edits preserve legacy UID project position and origin dates and use optimistic versions" do
    ref = @project.project_references.create!(@fields.merge(user: @user, uid: "1/α?%#笔记", position: 7, origin_created_at: 3.years.ago, origin_updated_at: 2.years.ago))
    identity = ref.attributes.slice("uid", "user_id", "project_id", "position", "created_at", "origin_created_at", "origin_updated_at")
    patch project_reference_path(@project, ref), params: { version: 0, reference: { title: "Renomeada", uid: "new", user_id: 42, project_id: @other.id } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal identity, ref.reload.attributes.slice(*identity.keys)
    assert_equal @fields[:url], ref.url
    assert_equal 1, ref.lock_version
    state = ref.attributes; parent = @project.reload.attributes
    patch project_reference_path(@project, ref), params: { version: 0, reference: { title: "Obsoleta" } }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "Renomeada", response.parsed_body.dig("reference", "title")
    assert_equal state, ref.reload.attributes
    assert_equal parent, @project.reload.attributes
    patch project_reference_path(@project, ref), params: { version: ref.lock_version, reference: { title: "Renomeada" } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal state, ref.reload.attributes
    assert_equal parent, @project.reload.attributes
  end

  test "archived project blocks commands opened earlier retains all records and restores editing" do
    ref = create_reference
    task = @user.tasks.create!(project: @project, title: "Preservada")
    @project.reload.archive!
    state = ref.attributes; parent = @project.attributes
    patch project_reference_path(@project, ref), params: { version: 0, reference: { title: "Bloqueada" } }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "project_archived", response.parsed_body["reason"]
    assert_equal false, response.parsed_body.dig("reference", "editable")
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields }, as: :json, headers: local_headers
    assert_response :conflict
    get edit_project_reference_path(@project, ref), headers: local_headers.merge("Turbo-Frame" => "reference-modal")
    assert_response :conflict
    assert_select "turbo-frame#reference-modal dialog", count: 1
    get project_path(@project, tab: "references"), headers: local_headers
    assert_select "[data-reference-uid]", count: 1
    assert_select "[data-reference-opener]", count: 0
    assert_select "a[target=_blank]", count: 1
    assert_equal state, ref.reload.attributes
    assert_equal parent, @project.reload.attributes
    assert_equal task.id, Task.first.id
    @project.restore!
    patch project_reference_path(@project, ref), params: { version: 0, reference: { title: "Restaurada" } }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "Restaurada", ref.reload.title
  end

  test "missing malformed and outside-context reference IDs return 404 and remain scoped" do
    ref = create_reference
    [ "bad", "u-@@", ref.to_param ].each do |token|
      get edit_project_reference_path(@other, token), headers: local_headers.merge("Turbo-Frame" => "reference-modal")
      assert_response :not_found
      assert_select "turbo-frame#reference-modal", count: 1
      patch project_reference_path(@other, token), params: { version: 0, reference: @fields }, as: :json, headers: local_headers
      assert_response :not_found
    end
    get project_path(@project, tab: "references", reference_dialog: "u-@@"), headers: local_headers
    assert_response :not_found
    @other.archive!
    patch project_reference_path(@other, ref), params: { version: 0, reference: @fields }, as: :json, headers: local_headers
    assert_response :not_found
    other_user = second_synthetic_user
    other_project = other_user.projects.create!(name: "Alheio")
    post project_references_path(other_project), params: { intent: @commands.issue(context: @project.uid), reference: @fields }, as: :json, headers: local_headers
    assert_response :not_found
    delete session_path, headers: local_headers
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields }, as: :json, headers: local_headers
    assert_response :unauthorized
  end

  test "validation rejects fields and rollback includes project activity" do
    ref = create_reference; state = ref.attributes; parent = @project.reload.attributes
    [ { title: "" }, { kind: "unknown" }, { title: "a" * 121 }, { description: "a" * 2001 }, { title: { bad: "data" } }, { kind: "link", url: "" } ].each do |fields|
      patch project_reference_path(@project, ref), params: { version: 0, reference: fields }, as: :json, headers: local_headers
      assert_response :unprocessable_entity
      assert_equal state, ref.reload.attributes
      assert_equal parent, @project.reload.attributes
    end
    connection = ProjectReference.connection
    connection.execute("CREATE TEMP TRIGGER qa_reference_parent_failure BEFORE UPDATE ON projects BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) { @commands.change(ref.uid, version: 0, attributes: { title: "Rollback" }, context: @project.uid) }
    assert_equal state, ref.reload.attributes
    assert_equal parent, @project.reload.attributes
    assert_raises(ActiveRecord::StatementInvalid) { create_reference(@fields.merge(title: "Rollback create")) }
    assert_equal 1, ProjectReference.count
    assert_equal parent, @project.reload.attributes
  ensure
    connection&.execute("DROP TRIGGER IF EXISTS temp.qa_reference_parent_failure")
  end

  test "direct forms redirect to canonical accessible dialogs and writes require CSRF" do
    ref = create_reference
    get new_project_reference_path(@project), headers: local_headers
    assert_redirected_to project_path(@project, tab: "references", reference_dialog: "new")
    get edit_project_reference_path(@project, ref), headers: local_headers
    assert_redirected_to project_path(@project, tab: "references", reference_dialog: ref.to_param)
    get new_project_reference_path(@project), headers: local_headers.merge("Turbo-Frame" => "reference-modal")
    assert_select "dialog[aria-labelledby=reference-dialog-title]", count: 1
    assert_select "input#reference-title[autofocus]", count: 1
    assert_select "input[name='reference[project_id]']", count: 0
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post project_references_path(@project), params: { intent: @commands.issue(context: @project.uid), reference: @fields }, as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://evil.test")
    assert_response :unprocessable_entity
    assert_equal 1, ProjectReference.count
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
