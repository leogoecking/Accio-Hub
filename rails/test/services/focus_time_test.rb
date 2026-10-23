require "test_helper"
require_relative "../support/focus_helpers"

class FocusTimeTest < ActiveSupport::TestCase
  setup do
    @clock = FocusTestClock.new
    @time = FocusTime.new(clock: @clock, observations: FocusTime::Observations.new)
    @anchor = @clock.sample
    @session = FocusSession.new(user_id: 1, uid: "clock/á", status: "running", started_at: @clock.wall,
      running_since: @clock.wall, deadline_at: @clock.wall + 1500)
  end

  test "nominal display advances without changing persisted checkpoint and caps at duration" do
    original = @session.attributes.deep_dup
    101.times do |index|
      projection = @time.project(@session, anchor: @anchor)
      assert_equal [ index * 15, 1500 ].min, projection.fetch("nominal_seconds")
      assert_equal 0, projection.fetch("checkpoint_seconds")
      assert_equal "observed", projection.fetch("continuity")
      @clock.advance(15)
    end
    assert_equal 0, @session.elapsed_seconds
    assert_equal original, @session.attributes
  end

  test "observation gap stays unknown even after frequent reads resume" do
    @clock.advance(61)
    assert_equal [ "observation_gap" ], @time.project(@session, anchor: @anchor).fetch("reasons")
    @clock.advance(15)
    assert_equal "unknown", @time.project(@session, anchor: @anchor).fetch("continuity")
  end

  test "wall jumps suspension divergence and reversed monotonic reject estimates" do
    [ [ -20, 1 ], [ 80, 1 ], [ 10, -1 ] ].each do |wall, mono|
      time = FocusTime.new(clock: @clock, observations: FocusTime::Observations.new)
      @clock.advance(wall, monotonic: mono)
      result = time.project(@session, anchor: @anchor)
      assert_equal "unknown", result.fetch("continuity")
      assert_not result.fetch("estimate_valid")
      assert result.fetch("nominal_seconds").between?(0, 1500)
      @clock.wall = Time.iso8601(@anchor.fetch("wall")); @clock.monotonic = @anchor.fetch("monotonic")
    end
  end

  test "process change and absent anchor cannot prove continuity" do
    @clock.epoch = "other-process"
    assert_includes @time.project(@session, anchor: @anchor).fetch("reasons"), "process_unknown"
    assert_includes @time.project(@session, anchor: nil).fetch("reasons"), "process_unknown"
  end

  test "inconsistent deadline is not silently repaired" do
    @session.deadline_at += 15
    assert_not @time.project(@session, anchor: @anchor).fetch("estimate_valid")
  end
end
