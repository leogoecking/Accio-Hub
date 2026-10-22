# No :environment: fail closed before Rails can open a default database.
namespace :sqlite_backups do
  def synthetic_sqlite_tool
    require_relative "../../app/services/synthetic_sqlite_backup"
    SyntheticSqliteBackup.new(fixture: ENV["ACCIO_SYNTHETIC_FIXTURE"], database: ENV["ACCIO_DATABASE_PATH"],
      environment: ENV["RAILS_ENV"], checkout: Rails.root.parent.to_s)
  end

  def synthetic_sqlite_task
    yield synthetic_sqlite_tool
  rescue SyntheticSqliteBackup::Busy
    abort "Contenção SQLite recuperável; nenhuma alteração na origem. Confira o destino privado antes de nova tentativa."
  rescue SyntheticSqliteBackup::Invalid, SystemCallError
    abort "Operação recusada ou não confirmada. Não sirva um destino incompleto; confira fixture e arquivos privados."
  end

  desc "Consistent SQLite backup, explicit private synthetic fixture only"
  task :create do
    synthetic_sqlite_task { |tool| puts JSON.pretty_generate(tool.backup(destination: ENV["ACCIO_SQLITE_BACKUP"])) }
  end

  desc "Verify complete private synthetic SQLite backup"
  task :verify do
    synthetic_sqlite_task { |tool| puts JSON.pretty_generate(tool.verify(ENV["ACCIO_SQLITE_BACKUP"])) }
  end

  desc "Restore into a NEW synthetic directory and revoke copied authentication sessions"
  task :restore do
    synthetic_sqlite_task { |tool| puts JSON.pretty_generate(tool.restore(archive: ENV["ACCIO_SQLITE_BACKUP"], directory: ENV["ACCIO_SQLITE_RESTORE_DIRECTORY"])) }
  end
end
