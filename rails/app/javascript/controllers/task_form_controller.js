import ProjectFormController from 'controllers/project_form_controller'
import { request, notice } from 'controllers/project_ui'
import { refreshTasks } from 'controllers/task_ui'

// Reuse the D1 dialog lifecycle, navigation guard, keyboard trap and focus return.
export default class extends ProjectFormController {
  connect() { super.connect(); this.form?.querySelector('#task-title').focus() }
  preview() { this.dirty = true }
  async submit(event) {
    event.preventDefault()
    if (this.pending || this.blocked || !this.form.reportValidity()) return
    this.pending = true; this.form.querySelector('[type=submit]').disabled = true
    try {
      const result = await request(this.form.action, new FormData(this.form))
      await refreshTasks()
      this.dirty = false; this.element.close(); this.afterClose()
      notice(document.querySelector('#task-surface, #project-surface, #dashboard-tasks'), result.message)
    } catch (error) {
      notice(this.element, error.message)
      this.remote = error.data?.task
      const remote = this.element.querySelector('[data-task-remote]')
      remote.hidden = !this.remote
      remote.textContent = this.remote ? `Versão salva: ${this.remote.title} · ${this.remote.priority === 'high' ? 'Alta' : 'Normal'} · ${this.remote.project_name} · ${this.remote.status}.` : ''
      this.element.querySelector('[data-task-reapply]').hidden = !this.remote?.editable || error.data?.reason === 'project_archived'
      this.element.querySelector('[data-task-reload]').hidden = !this.remote
    } finally {
      this.pending = false
      if (this.element.isConnected) this.form.querySelector('[type=submit]').disabled = !!this.blocked
    }
  }
  reapply() { this.form.elements.version.value = this.remote.lock_version; this.form.requestSubmit() }
  reload() {
    const project = this.form.querySelector('#task-project')
    if (project && this.remote.project_uid && !Array.from(project.options).some(option => option.value === this.remote.project_uid)) project.add(new Option(this.remote.project_name, this.remote.project_uid))
    for (const key of ['title', 'priority', 'project_uid']) {
      const input = this.form.elements.namedItem(`task[${key}]`)
      if (input) input.value = this.remote[key] || ''
    }
    this.form.elements.version.value = this.remote.lock_version
    this.blocked = !this.remote.editable
    this.form.querySelector('[type=submit]').disabled = this.blocked
    this.element.querySelector('[data-task-reapply]').hidden = true
    this.dirty = false
    notice(this.element, this.blocked ? 'Projeto arquivado; restaure antes de alterar a tarefa.' : 'Versão salva carregada. Confira os campos antes de editar.')
    this.form.querySelector('#task-title').focus()
  }
}
