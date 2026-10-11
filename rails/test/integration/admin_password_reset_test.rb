require "test_helper"

class AdminPasswordResetLoginTest < ActionDispatch::IntegrationTest
  test "reset invalidates existing HTTP sessions and authenticates only the new password" do
    administrator, old_password = synthetic_admin
    post session_path, params: { email_address: administrator.email_address, password: old_password }, headers: local_headers
    assert_redirected_to root_path
    previous_cookie = cookies["auth_session_id"]
    password = SecureRandom.hex(16)

    AdminPasswordReset.call(password: password, confirmation: password)

    assert_empty AuthSession.all
    assert_equal previous_cookie, cookies["auth_session_id"]
    get root_path, headers: local_headers
    assert_redirected_to new_session_path
    post session_path, params: { email_address: administrator.email_address, password: old_password }, headers: local_headers
    assert_response :unprocessable_entity
    assert_equal 0, AuthSession.count
    post session_path, params: { email_address: administrator.email_address, password: password }, headers: local_headers
    assert_redirected_to root_path
    get root_path, headers: local_headers
    assert_response :success
    assert_equal 1, AuthSession.count
  end

  test "password recovery has no HTTP endpoint" do
    [ "/admin/reset", "/passwords/new", "/passwords", "/password/reset" ].each do |path|
      %w[GET POST PATCH].each do |method|
        assert_raises(ActionController::RoutingError) do
          Rails.application.routes.recognize_path(path, method: method)
        end
      end
    end
  end
end
