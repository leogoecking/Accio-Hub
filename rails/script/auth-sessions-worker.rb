# Synthetic F3c subprocess, no HTTP and no application environment.
require "bundler/setup"
require "json"
require_relative "../app/services/synthetic_auth_session_cleanup"

$stdout.sync = true
begin
  tool = SyntheticAuthSessionCleanup.new(fixture: ENV["ACCIO_SYNTHETIC_FIXTURE"], database: ENV["ACCIO_DATABASE_PATH"],
    environment: ENV["RAILS_ENV"], checkout: File.expand_path("../..", __dir__),
    clock: -> { Time.iso8601(ENV.fetch("F3C_REFERENCE_TIME")) })
  mode = ENV.fetch("F3C_MODE")
  if mode == "cleanup"
    result = tool.cleanup(confirmation: SyntheticAuthSessionCleanup::CONFIRMATION) do |stage|
      if stage.to_s == ENV["F3C_HOLD_STAGE"]
        puts JSON.generate({ event: "held" })
        raise "Synthetic release missing" unless $stdin.gets&.strip == "release"
        raise IOError, "Synthetic transaction failure" if ENV["F3C_FAIL"] == "1"
      end
    end
    puts JSON.generate(result)
  elsif mode == "inventory"
    puts JSON.generate(tool.inventory)
  elsif mode == "writer"
    db = SQLite3::Database.new(ENV.fetch("ACCIO_DATABASE_PATH"), flags: SQLite3::Constants::Open::READWRITE)
    db.busy_timeout(5000)
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA synchronous=FULL")
    # Explicit writer lock in an independent synthetic process.
    db.execute("BEGIN IMMEDIATE")
    future = (Time.iso8601(ENV.fetch("F3C_REFERENCE_TIME")) + 43_200).strftime("%Y-%m-%d %H:%M:%S.%6N")
    case ENV.fetch("F3C_WRITE")
    when "logout" then db.execute("DELETE FROM auth_sessions WHERE id=?", [ Integer(ENV.fetch("F3C_ROW")) ])
    when "extend" then db.execute("UPDATE auth_sessions SET expires_at=? WHERE id=? AND user_id=1", [ future, Integer(ENV.fetch("F3C_ROW")) ])
    when "create" then db.execute("INSERT INTO auth_sessions(user_id,expires_at,created_at,updated_at) VALUES(1,?,?,?)", [ future, future, future ])
    when "lock" # Hold the real SQLite writer lock, without data changes.
    else raise "Unknown synthetic write"
    end
    puts JSON.generate({ event: "held" })
    raise "Synthetic release missing" unless $stdin.gets&.strip == "release"
    db.execute("COMMIT")
    puts JSON.generate({ committed: true })
  else
    raise "Unknown synthetic mode"
  end

rescue SyntheticAuthSessionCleanup::Busy
  puts JSON.generate({ status: "busy", committed: false })
  exit 75
rescue IOError
  puts JSON.generate({ status: "rolled_back", committed: false })
  exit 74
ensure
  db&.execute("ROLLBACK") if db&.transaction_active?
  db&.close
end
