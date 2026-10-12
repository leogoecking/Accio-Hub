require "test_helper"

class FoundationModelTest < ActiveSupport::TestCase
  test "one administrator is enforced by model and database" do
    synthetic_admin
    other = User.new(email_address: "other@example.test", password: "Aa1!#{SecureRandom.hex(16)}")
    assert_not other.valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      User.insert_all!([ { id: 2, email_address: "other@example.test", password_digest: "synthetic", created_at: Time.current, updated_at: Time.current } ])
    end
  end

  test "short passwords are refused" do
    assert_not User.new(email_address: "admin@example.test", password: "short").valid?
  end

  test "appearance rejects malformed and duplicated placement ids" do
    [ nil, [], { "dockOrder" => [ nil, "tasks" ] }, { "widgets" => [ { "id" => nil } ] }, { "widgets" => Array.new(7) { { "id" => "tasks" } } } ].each do |input|
      assert_equal Studio.defaults, Studio.appearance(input)
    end
  end

  test "all visibility ordering and spans are normalized" do
    p = Studio.defaults
    p["widgets"][0]["span"] = 100
    p["widgets"][1]["visible"] = "yes"
    p["dockHidden"] = [ "tasks", "tasks", "unknown" ]
    assert_equal 5, Studio.appearance(p)["widgets"][0]["span"]
    assert_equal true, Studio.appearance(p)["widgets"][1]["visible"]
    assert_equal [ "tasks" ], Studio.appearance(p)["dockHidden"]
  end
end
