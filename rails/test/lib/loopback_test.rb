require "test_helper"

class LoopbackTest < ActiveSupport::TestCase
  test "only real loopback peers pass the boundary" do
    app = LoopbackOnly.new(->(_env) { [ 200, {}, [ "OK" ] ] })
    %w[127.0.0.1 127.0.0.2 ::1].each { |ip| assert_equal 200, app.call("REMOTE_ADDR" => ip).first }
    [ "192.168.1.2", "0.0.0.0", "::", "bad", "" ].each { |ip| assert_equal 403, app.call("REMOTE_ADDR" => ip, "HTTP_X_FORWARDED_FOR" => "127.0.0.1").first }
  end

  test "server launcher refuses public binding forms" do
    %w[-b0.0.0.0 --binding=0.0.0.0].each do |argument|
      output = IO.popen([ Rails.root.join("bin/rails").to_s, "server", argument ], err: [ :child, :out ], &:read)
      assert_not $?.success?
      assert_match "somente binding", output
    end
  end
end
