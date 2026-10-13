require "json"
require "digest"
directory = ENV.fetch("ACCIO_QA_WORKSPACE")
raise "Synthetic only" unless Rails.env.development? && directory.start_with?(Rails.root.join("tmp/p12d2-browser-").to_s) && ActiveRecord::Base.connection_db_config.database == File.join(directory, "synthetic.sqlite3")
user = User.find_by!(email_address: "qa@example.test")
state = { tasks: user.tasks.order(:id).map(&:attributes), projects: user.projects.order(:id).map(&:attributes), preferences: AppearancePreferences.new(user).read }
mode = ENV.fetch("ACCIO_QA_MODE", "capture")
if mode == "capture"
  expected = JSON.parse(File.read(File.join(directory, "browser-state.json")))
  raise "Duplicate tasks" unless user.tasks.count == 2
  raise "UID replaced" unless user.tasks.map(&:to_param).sort == expected.values_at("personal", "contextual").sort
  personal = user.tasks.find_by!(uid: PublicUid.decode(expected.fetch("personal")))
  contextual = user.tasks.find_by!(uid: PublicUid.decode(expected.fetch("contextual")))
  raise "Personal link changed" if personal.project_id
  raise "Contextual link changed" unless contextual.project.to_param == expected.fetch("targetProject")
  raise "Other modules changed" unless ProjectReference.count.zero? && FocusSession.count.zero? && FocusCommand.count.zero?
  File.write(File.join(directory, "before-server-restart.json"), JSON.generate(state.as_json))
else
  raise "Data changed after restart" unless JSON.parse(File.read(File.join(directory, "before-server-restart.json"))) == JSON.parse(JSON.generate(state.as_json))
end
connection = Task.connection
raise "Trigger mismatch" unless connection.select_value("SELECT count(*) FROM sqlite_master WHERE type='trigger'") == 25
raise "FK violation" unless connection.select_all("PRAGMA foreign_key_check").empty?
result = { mode: mode, task_count: Task.count, project_count: Project.count, uid_links_intact: true, other_modules_empty: true, triggers: 25, foreign_keys_intact: true, wal: connection.select_value("PRAGMA journal_mode"), synchronous: connection.select_value("PRAGMA synchronous"), database_digest: Digest::SHA256.hexdigest(JSON.generate(state.as_json)) }
File.write(File.join(ENV.fetch("ACCIO_QA_EVIDENCE"), "browser-database-#{mode}.json"), JSON.pretty_generate(result) + "\n")
puts JSON.generate(result)
