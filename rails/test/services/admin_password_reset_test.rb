require "test_helper"
require "minitest/mock"

class AdminPasswordResetTest < ActiveSupport::TestCase
  test "valid reset changes only credentials and revokes active and expired sessions" do
    administrator, old_password = synthetic_admin
    administrator.auth_sessions.create!(expires_at: 1.hour.from_now)
    administrator.auth_sessions.create!(expires_at: 1.hour.ago)
    original = administrator.attributes.except("password_digest", "updated_at")
    password = SecureRandom.hex(16)

    AdminPasswordReset.call(password: password, confirmation: password)

    assert administrator.reload.authenticate(password)
    assert_not administrator.authenticate(old_password)
    assert_empty administrator.auth_sessions
    assert_equal original, administrator.attributes.except("password_digest", "updated_at")
  end

  test "invalid passwords and confirmation preserve the digest and sessions" do
    administrator, old_password = synthetic_admin
    session = administrator.auth_sessions.create!(expires_at: 1.hour.from_now)
    original = administrator.attributes
    valid_password = SecureRandom.hex(16)

    [ [ "", "" ], [ " " * 12, " " * 12 ], [ "short", "short" ], [ valid_password, "different" ], [ "a" * 73, "a" * 73 ] ].each do |password, confirmation|
      assert_raises(ActiveRecord::RecordInvalid) { AdminPasswordReset.call(password: password, confirmation: confirmation) }
      assert_equal original, administrator.reload.attributes
      assert administrator.authenticate(old_password)
      assert AuthSession.exists?(session.id)
    end
  end

  test "storage failure when revoking sessions rolls back the password change" do
    administrator, old_password = synthetic_admin
    session = administrator.auth_sessions.create!(expires_at: 1.hour.from_now)
    original = administrator.attributes
    password = SecureRandom.hex(16)
    association = administrator.auth_sessions

    User.stub(:lock, User) do
      User.stub(:find, administrator) do
        association.stub(:delete_all, -> { raise ActiveRecord::StatementInvalid, "Synthetic storage failure" }) do
          assert_raises(ActiveRecord::StatementInvalid) { AdminPasswordReset.call(password: password, confirmation: password) }
        end
      end
    end

    assert_equal original, administrator.reload.attributes
    assert administrator.authenticate(old_password)
    assert_not administrator.authenticate(password)
    assert AuthSession.exists?(session.id)
  end

  test "missing administrator causes no writes" do
    password = SecureRandom.hex(16)
    assert_raises(ActiveRecord::RecordNotFound) { AdminPasswordReset.call(password: password, confirmation: password) }
    assert_equal 0, User.count
    assert_equal 0, AuthSession.count
  end
end
