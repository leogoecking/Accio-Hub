require "test_helper"

class FoundationTest < ActionDispatch::IntegrationTest
  test "all studio routes require a session" do
    [ root_path, *Studio::PAGES.map { |page| app_path(page) } ].each do |path|
      get path, headers: local_headers
      assert_redirected_to new_session_path
    end
    patch "/appearance", params: { appearance: { theme: "light" } }, as: :json, headers: local_headers
    assert_response :unauthorized
  end

  test "invalid authentication never starts a session" do
    synthetic_admin
    post session_path, params: { email_address: "admin@example.test", password: "invalid" }, headers: local_headers
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: "E-mail ou senha inválidos."
    assert_equal 0, AuthSession.count
  end

  test "authentication normalizes email and expires server side" do
    user, password = synthetic_admin
    post session_path, params: { email_address: " ADMIN@EXAMPLE.TEST ", password: password }, headers: local_headers
    assert_redirected_to root_path
    assert_equal user.id, AuthSession.last.user_id
    assert_match(/httponly/i, response.headers["Set-Cookie"].join)
    assert_match(/samesite=strict/i, response.headers["Set-Cookie"].join)
    AuthSession.last.update!(expires_at: 1.minute.ago)
    get root_path, headers: local_headers
    assert_redirected_to new_session_path
  end

  test "logout revokes the server session" do
    sign_in
    delete session_path, headers: local_headers
    assert_redirected_to new_session_path
    assert_equal 0, AuthSession.count
    get root_path, headers: local_headers
    assert_redirected_to new_session_path
  end

  test "all supported pages render with isolated demo data" do
    sign_in
    Studio::PAGES.each do |page|
      get studio_path_for_test(page), headers: local_headers
      follow_redirect! if %w[projects tasks].include?(page)
      assert_response :success
      assert_select "main", count: 1
      assert_select "nav[aria-label='Navegação principal']", count: 1
      assert_select "dialog", count: 4
      assert_select "dialog.focus-dialog[aria-labelledby=focus-dialog-title]", count: 1
      assert_select "h1", count: 1
      assert_match "no-store", response.headers["Cache-Control"]
    end
  end

  test "unknown routes are rejected and there is no registration" do
    sign_in
    get app_path("unknown"), headers: local_headers
    assert_response :not_found
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/sign_up") }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/users", method: :post) }
  end

  test "preferences survive reload and do not write projects tasks notes or focus" do
    sign_in
    post "/appearance/bootstrap", as: :json, headers: local_headers
    domain_counts = [ Project, Task, ProjectReference, FocusSession, FocusCommand ].to_h { |model| [ model.name, model.count ] }
    preferences = Studio.defaults.merge("theme" => "light", "accent" => "#aabbcc", "wallpaper" => "ember", "music" => false)
    preferences["widgets"].first["span"] = 8
    patch "/appearance", params: { appearance: preferences, version: 0 }, as: :json, headers: local_headers
    assert_response :success
    assert_equal preferences, response.parsed_body["appearance"]
    get root_path, headers: local_headers
    assert_select "html[data-theme=light][data-wallpaper=ember]"
    assert_select ".panel-tasks.span-8"
    assert_equal domain_counts, [ Project, Task, ProjectReference, FocusSession, FocusCommand ].to_h { |model| [ model.name, model.count ] }
    assert_equal %w[ar_internal_metadata auth_sessions dock_shortcuts focus_commands focus_sessions project_references projects schema_migrations tasks user_preferences users widget_placements], ActiveRecord::Base.connection.tables.sort
  end

  test "appearance validates adversarial values" do
    sign_in
    patch "/appearance", params: { appearance: { theme: "<script>", accent: "red;display:none", dockOrder: [ "tasks", nil ], widgets: [ { span: 3 } ], unexpected: "ignored" } }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 0, UserPreference.count
  end

  test "SQLite preferences control authenticated appearance" do
    user = sign_in
    store = AppearancePreferences.new(user)
    store.bootstrap(legacy: nil, raw: nil)
    appearance = Studio.defaults.merge("theme" => "light", "wallpaper" => "ocean")
    store.update(appearance, version: 0)
    get root_path, headers: local_headers
    assert_select "html[data-theme=light][data-wallpaper=ocean]"
    patch "/appearance", params: { appearance: appearance.merge("wallpaper" => "ember"), version: 1 }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "ember", user.user_preference.reload.wallpaper
    assert_equal 8, DockShortcut.count
    assert_equal 7, WidgetPlacement.count
  end

  test "login keeps the saved browser appearance after logout" do
    sign_in
    post "/appearance/bootstrap", as: :json, headers: local_headers
    patch "/appearance", params: { appearance: Studio.defaults.merge("theme" => "light"), version: 0 }, as: :json, headers: local_headers
    delete session_path, headers: local_headers
    get new_session_path, headers: local_headers
    assert_select "html[data-theme=light]"
    post session_path, params: { email_address: "admin@example.test", password: "invalid" }, headers: local_headers
    assert_response :unprocessable_entity
    assert_select "html[data-theme=light]"
  end

  test "rate limit rejects repeated incorrect authentication" do
    9.times { post session_path, params: { email_address: "missing@example.test", password: "invalid" }, headers: local_headers }
    assert_redirected_to new_session_path
    assert_equal 0, AuthSession.count
  end

  test "cross site requests cannot mutate appearance" do
    sign_in
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    patch "/appearance", params: { appearance: { theme: "light" } }, as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://untrusted.example")
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  private

  def studio_path_for_test(page)
    page == "home" ? root_path : app_path(page)
  end
end
