require "test_helper"

class AppearancePersistenceTest < ActionDispatch::IntegrationTest
  setup { @user = sign_in }

  def bootstrap
    post "/appearance/bootstrap", as: :json, headers: local_headers
    assert_response :success
  end

  def legacy_cookie(value)
    jar = ActionDispatch::Cookies::CookieJar.build(request, {})
    jar.encrypted[:accio_appearance] = { value: value, httponly: true, same_site: :strict }
    cookies[:accio_appearance] = jar[:accio_appearance]
  end

  test "encrypted legacy cookie is validated imported and removed after confirmation" do
    value = Studio.defaults.merge("theme" => "light", "wallpaper" => "ocean")
    legacy_cookie(value)
    bootstrap
    assert_equal value, response.parsed_body["appearance"]
    assert_equal value, @user.user_preference.legacy_cookie_backup["value"]
    assert response.headers["Set-Cookie"].to_s.include?("accio_appearance=")
    assert cookies[:accio_appearance].blank?
    get root_path, headers: local_headers
    assert_select "html[data-theme=light][data-wallpaper=ocean]"
  end

  test "another encrypted cookie cannot replace existing SQLite preferences" do
    bootstrap
    value = Studio.defaults.merge("theme" => "light")
    legacy_cookie(value)
    post "/appearance/bootstrap", as: :json, headers: local_headers
    assert_response :conflict
    assert_equal "legacy_conflict", response.parsed_body["error"]
    assert cookies[:accio_appearance]
    assert_equal "dark", @user.user_preference.reload.theme
    post "/appearance/bootstrap", params: { resolution: "keep_database", version: 0 }, as: :json, headers: local_headers
    assert_response :success
    assert cookies[:accio_appearance].blank?
    assert_equal value, @user.user_preference.reload.legacy_cookie_backup["retained_candidates"].values.first["value"]
  end

  test "tampered cookie remains recoverable and requires explicit defaults" do
    cookies[:accio_appearance] = "synthetic-invalid-ciphertext"
    post "/appearance/bootstrap", as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal true, response.parsed_body["allow_defaults"]
    assert cookies[:accio_appearance]
    assert_equal 0, UserPreference.count
    post "/appearance/bootstrap", params: { resolution: "use_defaults" }, as: :json, headers: local_headers
    assert_response :success
    assert_equal "synthetic-invalid-ciphertext", @user.user_preference.legacy_cookie_backup["raw"]
    assert cookies[:accio_appearance].blank?
  end

  test "presentation cache never seeds the operational aggregate" do
    jar = ActionDispatch::Cookies::CookieJar.build(request, {})
    jar.encrypted[:accio_presentation] = { value: { "theme" => "light", "accent" => "#aabbcc" } }
    cookies[:accio_presentation] = jar[:accio_presentation]
    bootstrap
    assert_equal Studio.defaults, response.parsed_body["appearance"]
    assert_nil @user.user_preference.legacy_cookie_backup
  end

  test "GET never initializes and POST bootstraps before versioned writes" do
    get root_path, headers: local_headers
    assert_equal 0, UserPreference.count
    bootstrap
    value = Studio.defaults.merge("accent" => "#aa33cc")
    patch "/appearance", params: { appearance: value, version: 0 }, as: :json, headers: local_headers
    assert_response :success
    assert_equal 1, response.parsed_body["version"]
    patch "/appearance", params: { appearance: Studio.defaults, version: 0 }, as: :json, headers: local_headers
    assert_response :conflict
    assert_equal value, response.parsed_body["appearance"]
    assert_equal "#aa33cc", @user.user_preference.reload.accent
  end

  test "old clients and invalid complete DTO cannot overwrite initialized preferences" do
    bootstrap
    patch "/appearance", params: { appearance: Studio.defaults }, as: :json, headers: local_headers
    assert_response :conflict
    patch "/appearance", params: { appearance: Studio.defaults.merge("unknown" => "value"), version: 0 }, as: :json, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 0, @user.user_preference.lock_version
  end

  test "cookie deletion is not returned when bootstrap transaction fails" do
    failure = SQLite3::BusyException.new("Synthetic busy")
    error = ActiveRecord::StatementInvalid.new("Synthetic busy")
    store = AppearancePreferences.new(@user)
    store.define_singleton_method(:bootstrap) { |**| raise error, cause: failure }
    AppearancePreferences.stub(:new, store) do
      post "/appearance/bootstrap", as: :json, headers: local_headers
    end
    assert_response :service_unavailable
    assert_equal "database_busy", response.parsed_body["error"]
    assert_not response.headers["Set-Cookie"].to_s.include?("accio_appearance=")
    assert_equal 0, UserPreference.count
  end

  test "bootstrap is authenticated and CSRF protected" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/appearance/bootstrap", as: :json, headers: local_headers.merge("HTTP_ORIGIN" => "https://invalid.example")
    assert_response :unprocessable_entity
    assert_equal 0, UserPreference.count
    ActionController::Base.allow_forgery_protection = previous
    delete session_path, headers: local_headers
    post "/appearance/bootstrap", as: :json, headers: local_headers
    assert_response :unauthorized
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
