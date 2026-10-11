ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  def synthetic_admin
    password = "Aa1!#{SecureRandom.hex(16)}"
    [ User.create!(email_address: "admin@example.test", password: password), password ]
  end
end

class ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    Rails.cache.clear
  end

  def local_headers
    { "REMOTE_ADDR" => "127.0.0.1" }
  end

  def sign_in
    user, password = synthetic_admin
    post session_path, params: { email_address: user.email_address, password: password }, headers: local_headers
    assert_redirected_to root_path
    user
  end
end
