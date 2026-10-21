# Nominal time is a projection, not evidence of work. Observations are volatile
# and advisory: losing them can only make continuity less certain.
class FocusTime
  OBSERVATION_INTERVAL = 15
  MAX_GAP = 60
  MAX_DIVERGENCE = 5

  class Clock
    NONCE = SecureRandom.hex(12).freeze

    def sample
      { "wall" => Time.current.iso8601(6), "monotonic" => Process.clock_gettime(Process::CLOCK_MONOTONIC),
        "epoch" => "#{Process.pid}:#{NONCE}" }
    end
  end

  class Observations
    def initialize
      @mutex = Mutex.new
      @entries = {}
    end

    def check(key, anchor, sample)
      @mutex.synchronize do
        entry = @entries[key.first]
        entry = nil unless entry && entry[:key] == key
        reasons = entry ? entry[:reasons].dup : []
        valid = entry ? entry[:valid] : true
        previous = entry ? entry[:sample] : anchor
        if !anchor || anchor["epoch"] != sample["epoch"]
          reasons << "process_unknown"
        else
          wall_delta = Time.iso8601(sample.fetch("wall")) - Time.iso8601(anchor.fetch("wall"))
          monotonic_delta = sample.fetch("monotonic") - anchor.fetch("monotonic")
          if monotonic_delta < 0 || (wall_delta - monotonic_delta).abs > MAX_DIVERGENCE
            reasons << "clock_divergence"
            valid = false
          end
        end
        if previous && previous["epoch"] == sample["epoch"]
          gap = Time.iso8601(sample.fetch("wall")) - Time.iso8601(previous.fetch("wall"))
          reasons << "observation_gap" if gap > MAX_GAP
        end
        @entries[key.first] = { key: key, sample: sample, reasons: reasons.uniq, valid: valid }
        [ reasons.uniq, valid ]
      end
    end
  end

  OBSERVATIONS = Observations.new

  def initialize(clock: Clock.new, observations: OBSERVATIONS)
    @clock = clock
    @observations = observations
  end

  def sample
    @clock.sample
  end

  def project(session, anchor:, sample: self.sample)
    checkpoint = session.elapsed_seconds
    nominal = checkpoint
    reasons = []
    valid = true
    if session.status == "running"
      delta = Time.iso8601(sample.fetch("wall")) - session.running_since
      expected_deadline = session.running_since + session.duration_seconds - checkpoint
      reasons, valid = @observations.check([ session.user_id, session.uid, session.lock_version ], anchor, sample)
      if delta < 0 || (session.deadline_at - expected_deadline).abs > 0.001
        reasons |= [ "inconsistent_clock" ]
        valid = false
      end
      nominal = [ session.duration_seconds, checkpoint + [ delta, 0 ].max.floor ].min
    end
    { "checkpoint_seconds" => checkpoint, "nominal_seconds" => nominal,
      "remaining_seconds" => session.duration_seconds - nominal,
      "continuity" => session.status == "running" ? (reasons.empty? ? "observed" : "unknown") : "not_running",
      "reasons" => reasons, "estimate_valid" => valid }
  end
end
