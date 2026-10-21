module FocusHelper
  # Presentation hints only: all versions/context are revalidated by E1.
  def focus_context(project: nil, task: nil)
    {}.tap do |context|
      context.merge!(project_uid: project.to_param, project_version: project.lock_version) if project
      context.merge!(task_uid: task.to_param, task_version: task.lock_version) if task
    end
  end

  def focus_catalog
    {
      projects: Current.user.projects.select(:uid, :name, :lock_version, :status).map { |p| { uid: p.uid, name: p.name, version: p.lock_version, archived: p.status == "archived" } },
      tasks: Current.user.tasks.select(:uid, :title, :lock_version, :status).map { |t| { uid: t.uid, name: t.title, version: t.lock_version, completed: t.status == "completed" } }
    }
  end
end
