require "test_helper"

class FocusTest < ActionDispatch::IntegrationTest
  setup do
    @user = sign_in
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
  end

  def prepare_http(operation = "start_new")
    post "/focus/intents", params: {}, as: :json, headers: local_headers
    assert_response :success
    intent = response.parsed_body.fetch("intent")
    body = { intent: intent, command_id: SecureRandom.uuid, version: 0, operation: operation }
    post "/focus/prepare", params: body, as: :json, headers: local_headers
    assert_response :success
    [ FocusSession.first, body ]
  end

  def saved_rows
    [ FocusSession.order(:id).map(&:attributes), FocusCommand.order(:id).map(&:attributes), UserPreference.order(:id).map(&:attributes),
      Project.order(:id).map(&:attributes), Task.order(:id).map(&:attributes), AuthSession.order(:id).map(&:attributes) ]
  end

  test "repeated GET state does not create write or confirm anything" do
    before = saved_rows
    4.times { get "/focus/state", as: :json, headers: local_headers; assert_response :success; assert_nil response.parsed_body.fetch("session") }
    assert_equal before, saved_rows
    session, = prepare_http
    before = saved_rows
    writes = []
    listener = ->(_name, _start, _finish, _id, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i) }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
      4.times { get "/focus/state", as: :json, headers: local_headers; assert_response :success }
    end
    assert_empty writes
    assert_equal before, saved_rows
    assert_equal session.uid, response.parsed_body.dig("session", "uid")
    assert response.headers.fetch("Cache-Control").include?("no-store")
  end

  test "HTTP lost response replay returns historical result and current state separately" do
    session, body = prepare_http
    historical = response.parsed_body.fetch("result")
    post "/focus/#{session.to_param}/commands", params: { command_id: "pause-http", version: session.lock_version, kind: "pause", parameters: { action: "pause" } }, as: :json, headers: local_headers
    assert_response :success
    post "/focus/prepare", params: body, as: :json, headers: local_headers
    assert_response :success
    assert_equal historical, response.parsed_body.fetch("result")
    assert response.parsed_body.fetch("replayed")
    assert_equal "paused", response.parsed_body.dig("current", "session", "status")
    post "/focus/#{session.to_param}/commands", params: { command_id: "obsolete", version: session.lock_version, kind: "start", parameters: { action: "resume" } }, as: :json, headers: local_headers
    assert_response :conflict
    post "/focus/prepare", params: body.merge(operation: "prepare"), as: :json, headers: local_headers
    assert_response :conflict
    assert_equal 1, FocusSession.count
  end

  test "HTTP scoped UIDs strict input versions and presets have defined failures" do
    session, = prepare_http("prepare")
    [ "bad", PublicUid.encode("missing/á") ].each do |uid|
      post "/focus/#{uid}/commands", params: { command_id: "invalid-uid", version: 0, kind: "reset", parameters: { action: "cancel" } }, as: :json, headers: local_headers
      assert_response :not_found
    end
    post "/focus/#{session.to_param}/commands", params: { command_id: "no-version", kind: "reset", parameters: { action: "cancel" } }, as: :json, headers: local_headers
    assert_response :conflict
    post "/focus/#{session.to_param}/commands", params: { command_id: "injected", version: 0, kind: "reset", parameters: { action: "cancel", elapsed_seconds: 1500 } }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    post "/focus/intents", params: { context: { project_uid: PublicUid.encode("other") } }, as: :json, headers: local_headers
    assert_response :not_found
    post "/focus/intents", params: { user_id: 2 }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    patch "/focus/preset", params: { duration_seconds: 200, version: 0 }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    post "/focus/#{session.to_param}/commands", params: { command_id: "cancel-http", version: 0, kind: "reset", parameters: { action: "cancel" } }, as: :json, headers: local_headers
    assert_response :success
    patch "/focus/preset", params: { duration_seconds: 2700, version: 0 }, as: :json, headers: local_headers
    assert_response :success
    assert_equal 2700, @user.user_preferences_scope.first.focus_duration_seconds
    assert_equal 1, FocusSession.count
  end

  test "CSRF and authentication are preserved with shared operational timer" do
    get root_path, headers: local_headers
    assert_select "[data-demo=focus]", count: 0
    assert_select "[data-controller~=focus]", count: 1
    assert_select "[data-focus-primary]", count: 1
    assert_select "dialog[data-focus-target=dialog][aria-labelledby=focus-dialog-title]"
    assert_equal 0, FocusSession.count
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/focus/intents", params: {}, as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://evil.test")
    assert_response :unprocessable_entity
    assert_equal 0, FocusSession.count
    ActionController::Base.allow_forgery_protection = previous
    delete session_path, headers: local_headers
    get "/focus/state", as: :json, headers: local_headers
    assert_response :unauthorized
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
