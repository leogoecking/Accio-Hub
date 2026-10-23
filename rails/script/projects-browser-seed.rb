# Synthetic fixtures solely for browser read-only relationship/legacy UID checks.
workspace = ENV.fetch("ACCIO_QA_WORKSPACE")
expected = File.join(workspace, "synthetic.sqlite3")
abort "Synthetic QA database required" unless Rails.env.development? && workspace.start_with?(Rails.root.join("tmp/p12d-browser-").to_s) && ActiveRecord::Base.connection_db_config.database == expected
abort "Unexpected account or prior state" unless User.first.email_address == "qa@example.test" && Project.count == 1 && Project.first.name.start_with?("Projeto Navegador QA")
user = User.first
project = user.projects.create!(uid: "42/á?%#项目", name: "Legado Unicode QA", description: "Fixture sintética de vínculos", icon: "code", tint: "purple", origin_created_at: 2.years.ago, origin_updated_at: 1.year.ago)
user.tasks.create!(project: project, uid: "1", title: "Tarefa vinculada QA", priority: "high")
user.project_references.create!(project: project, uid: "1", title: "Material QA", kind: "material", description: "Somente descrição")
user.project_references.create!(project: project, uid: "2", title: "Link QA", kind: "link", url: "https://example.test/material", position: 1)
user.widget_placements.create!(project: project, context: "project", widget_key: "tasks", position: 0, span: 5)
user.focus_sessions.create!(project: project)
user.projects.create!(uid: "1", name: "Projeto 2 QA", icon: "target", tint: "pink")
user.projects.create!(uid: "legacy4", name: "Projeto 10 QA", icon: "rss", tint: "orange")
require "json"
File.write(File.join(workspace, "d1-snapshot.json"), JSON.generate({ projects: Project.order(:id).map(&:attributes), preferences: AppearancePreferences.new(user).read }.as_json), mode: "w", perm: 0o600)
puts "Synthetic legacy UID and read-only relationship fixtures prepared."
