class FocusTestClock
  attr_accessor :wall, :monotonic, :epoch

  def initialize
    @wall = Time.current.change(usec: 0)
    @monotonic = 1000.0
    @epoch = "synthetic-clock"
  end

  def advance(seconds, monotonic: seconds)
    @wall += seconds.to_s.to_r
    @monotonic += monotonic
  end

  def sample
    { "wall" => wall.iso8601(6), "monotonic" => monotonic, "epoch" => epoch }
  end
end

module FocusHelpers
  def focus_setup
    @user = synthetic_admin.first
    AppearancePreferences.new(@user).bootstrap(legacy: nil, raw: nil)
    @clock = FocusTestClock.new
    @time = FocusTime.new(clock: @clock, observations: FocusTime::Observations.new)
    @engine = FocusCommands.new(@user, time: @time)
  end

  def create_focus(action: "start_new", context: {}, duration: nil)
    result = @engine.prepare(intent: @engine.issue(context: context, duration: duration), command_id: SecureRandom.uuid,
      version: 0, action: action)
    @user.focus_sessions.find_by!(uid: result.fetch("result").fetch("session").fetch("uid"))
  end

  def focus_action(session, action, **parameters)
    result = @engine.command(uid: session.uid, command_id: SecureRandom.uuid, version: session.reload.lock_version,
      kind: FocusCommands::ACTIONS.find { |_kind, actions| actions.include?(action) }.first,
      parameters: { "action" => action }.merge(parameters.stringify_keys))
    session.reload
    result
  end

  def focus_rows
    [ FocusSession.order(:id).map(&:attributes), FocusCommand.order(:id).map(&:attributes), UserPreference.order(:id).map(&:attributes) ]
  end

  def context_for(project = nil, task = nil)
    { "project_uid" => project&.uid, "project_version" => project&.reload&.lock_version,
      "task_uid" => task&.uid, "task_version" => task&.reload&.lock_version }.compact
  end
end
