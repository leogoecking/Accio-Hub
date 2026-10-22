#!/usr/bin/env ruby
require "bundler/setup"
require_relative "../app/services/synthetic_sqlite_backup"

begin
  tool = SyntheticSqliteBackup.new(fixture: ENV["ACCIO_SYNTHETIC_FIXTURE"], database: ENV["ACCIO_DATABASE_PATH"],
    environment: ENV["RAILS_ENV"], checkout: File.expand_path("../..", __dir__))
  directory = ENV.fetch("ACCIO_SQLITE_RESTORE_DIRECTORY")
  secret = tool.runtime(directory: directory)
  pidfile = File.expand_path(ENV.fetch("PIDFILE"))
  unless File.dirname(pidfile) == File.realpath(directory) && pidfile.end_with?(".pid") && !File.exist?(pidfile) && !File.symlink?(pidfile)
    raise SyntheticSqliteBackup::Invalid, "PID privado novo obrigatório"
  end
  port = Integer(ENV.fetch("PORT"))
  raise SyntheticSqliteBackup::Invalid unless (1024..65535).cover?(port)
  # Secrets are environment-only, not process arguments, logs, package or readiness JSON.
  exec({ "SECRET_KEY_BASE" => secret, "SECRET_KEY_BASE_DUMMY" => nil }, File.expand_path("../bin/rails", __dir__), "server", "-b", "127.0.0.1", "-p", port.to_s)
rescue SyntheticSqliteBackup::Invalid, KeyError, SystemCallError, ArgumentError
  abort "HTTP não iniciado: preparação sintética segura não comprovada."
end
