module TasksHelper
  def task_edit_url(task, context = nil)
    context ? edit_project_task_path(context, task) : edit_task_path(task)
  end

  def task_status_url(task, context = nil)
    context ? status_project_task_path(context, task) : status_task_path(task)
  end

  def task_new_url(context = nil)
    context ? new_project_task_path(context) : new_task_path
  end
end
