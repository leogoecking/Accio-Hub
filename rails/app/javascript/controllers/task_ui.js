import { refresh } from 'controllers/project_ui'
export async function refreshTasks() {
  if (document.getElementById('task-surface')) await refresh(window.location.href, 'task-surface')
  else if (document.getElementById('project-surface')) await refresh()
  else for (const target of ['dashboard-tasks', 'dashboard-counts', 'dashboard-projects']) {
    if (document.getElementById(target)) await refresh(window.location.href, target)
  }
}
