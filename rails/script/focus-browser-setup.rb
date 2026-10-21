#!/usr/bin/env ruby
# NEW synthetic database only. Clock injection stays inside this private QA server.
require "tmpdir"
require "open3"
require "json"
root = File.expand_path("..", __dir__)
directory = Dir.mktmpdir("p12e2-browser-", File.join(root, "tmp"))
File.chmod(0o700, directory)
seed = File.join(directory, "seed.rb")
File.write(seed, <<~'RUBY')
  require "json"
  Rails.logger.level = Logger::WARN
  directory = ENV.fetch("E2_WORKSPACE")
  raise "Synthetic only" unless ActiveRecord::Base.connection_db_config.database == File.join(directory, "synthetic.sqlite3")
  password = SecureRandom.hex(24)
  user = User.create!(email_address: "focus-qa@example.test", password: password)
  AppearancePreferences.new(user).bootstrap(legacy: nil, raw: nil)
  project = user.projects.create!(uid: "42/á?%#项目", name: "Projeto foco QA")
  other = user.projects.create!(name: "Outro projeto QA")
  task = user.tasks.create!(uid: "task/á%?#", title: "Tarefa contextual QA", project: project)
  personal = user.tasks.create!(title: "Tarefa pessoal QA")
  File.write(File.join(directory, "credentials.json"), JSON.generate({ email: user.email_address, password: password }), mode: "w", perm: 0o600)
  File.write(File.join(directory, "state.json"), JSON.generate({ project: project.to_param, other: other.to_param, task: task.to_param, personal: personal.to_param }))
  File.write(File.join(directory, "clock.json"), JSON.generate({ wall: Time.current.change(usec: 0).iso8601(6), monotonic: 1000 }))
RUBY
server = File.join(directory, "server.rb")
File.write(server, <<~'RUBY')
  require File.expand_path("config/application", Dir.pwd)
  Rails.application.initialize!
  directory = ENV.fetch("E2_WORKSPACE")
  raise "Synthetic only" unless directory.start_with?(Rails.root.join("tmp/p12e2-browser-").to_s) && ActiveRecord::Base.connection_db_config.database == File.join(directory, "synthetic.sqlite3")
  class SyntheticFocusClock
    def sample
      data = JSON.parse(File.read(File.join(ENV.fetch("E2_WORKSPACE"), "clock.json")))
      { "wall" => data.fetch("wall"), "monotonic" => data.fetch("monotonic"), "epoch" => "synthetic-#{Process.pid}" }
    end
  end
  install_clock = -> do
    FocusController.class_eval do
      private
      def engine
        @engine ||= FocusCommands.new(Current.user, time: FocusTime.new(clock: SyntheticFocusClock.new))
      end
    end
  end
  Rails.application.reloader.to_prepare(&install_clock)
  install_clock.call
  require "rackup"
  Rackup::Handler.get("puma").run(Rails.application, Host: "127.0.0.1", Port: 3127, Threads: "1:4", Silent: true)
RUBY
env = { "RAILS_ENV" => "development", "ACCIO_DATABASE_PATH" => File.join(directory, "synthetic.sqlite3"), "E2_WORKSPACE" => directory }
[ [ "bin/rails", "db:schema:load" ], [ "bin/rails", "runner", seed ] ].each do |command|
  output, errors, status = Open3.capture3(env, *command, chdir: root)
  raise "Synthetic setup failed: #{errors} #{output}" unless status.success?
end
File.write(File.join(root, "tmp/p12e2-workspace"), directory + "\n")
puts "Synthetic workspace created. Start with bundle exec ruby and its private server.rb (loopback :3127)."
