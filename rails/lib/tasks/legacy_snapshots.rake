# Deliberately no :environment dependency: reject operational databases before connecting.
namespace :legacy_snapshots do
  def snapshot_archive
    require_relative "../../app/services/legacy_snapshot_archive"
    LegacySnapshotArchive.new(fixture: ENV["ACCIO_SYNTHETIC_FIXTURE"], database: ENV["ACCIO_DATABASE_PATH"],
      environment: ENV["RAILS_ENV"], checkout: Rails.root.parent.to_s)
  end

  def snapshot_task
    yield snapshot_archive
  rescue LegacySnapshotArchive::Invalid, SystemCallError
    abort "Operação recusada ou não confirmada; nenhum snapshot do banco foi alterado. Confira fixture, estrutura e destino privados."
  end

  desc "Inventory legacy snapshots (explicit private synthetic fixture only; read-only)"
  task :inventory do
    snapshot_task { |archive| puts JSON.pretty_generate(archive.inventory) }
  end

  desc "Export legacy snapshots to explicit private ACCIO_SNAPSHOT_DESTINATION (synthetic only)"
  task :export do
    snapshot_task do |archive|
      content = archive.export(destination: ENV["ACCIO_SNAPSHOT_DESTINATION"])
      puts JSON.pretty_generate({ verified: true, format_version: content["version"], inventory: content["inventory"] })
    end
  end

  desc "Reopen and verify ACCIO_SNAPSHOT_ARCHIVE (synthetic only; prints no private content)"
  task :verify do
    snapshot_task do |archive|
      content = archive.verify(ENV["ACCIO_SNAPSHOT_ARCHIVE"])
      puts JSON.pretty_generate({ verified: true, format_version: content["version"], inventory: content["inventory"] })
    end
  end
end
