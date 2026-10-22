# Deliberately no :environment; refuse before Rails can open the default database.
namespace :admin do
  namespace :sessions do
    def synthetic_session_maintenance
      require_relative "../../app/services/synthetic_auth_session_cleanup"
      tool = SyntheticAuthSessionCleanup.new(fixture: ENV["ACCIO_SYNTHETIC_FIXTURE"], database: ENV["ACCIO_DATABASE_PATH"],
        environment: ENV["RAILS_ENV"], checkout: Rails.root.parent.to_s)
      yield tool
    rescue SyntheticAuthSessionCleanup::Busy
      abort "Contenção SQLite recuperável. Nenhuma limpeza confirmada; execute novamente por decisão explícita."
    rescue SyntheticAuthSessionCleanup::Invalid, SystemCallError
      abort "Operação recusada ou revertida. Confira ambiente test, fixture privada, banco explícito e confirmação."
    end

    desc "Read-only expired authentication session inventory (synthetic test database only)"
    task :inventory do
      synthetic_session_maintenance { |tool| puts JSON.pretty_generate(tool.inventory) }
    end

    desc "Dry-run by default; requires ACCIO_SESSION_CLEANUP_CONFIRM=DELETE_EXPIRED_AUTH_SESSIONS for deletion"
    task :cleanup do
      synthetic_session_maintenance do |tool|
        confirmation = ENV["ACCIO_SESSION_CLEANUP_CONFIRM"]
        result = if confirmation.nil?
          tool.inventory
        else
          tool.cleanup(confirmation: confirmation)
        end
        puts JSON.pretty_generate(result)
      end
    end
  end
end
