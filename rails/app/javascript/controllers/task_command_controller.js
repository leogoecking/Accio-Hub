import { Controller } from '@hotwired/stimulus'
import { request, notice, restoreFocus } from 'controllers/project_ui'
import { refreshTasks } from 'controllers/task_ui'
export default class extends Controller {
  change() { this.element.requestSubmit() }
  async submit(event) {
    event.preventDefault()
    if (this.pending) return
    const checkbox = this.element.querySelector('[type=checkbox]'), id = checkbox.id
    this.pending = true; checkbox.disabled = true
    try {
      const result = await request(this.element.action, new FormData(this.element))
      await refreshTasks(); restoreFocus(id)
      notice(document.querySelector('#task-surface, #project-surface, #dashboard-tasks'), result.message)
    } catch (error) {
      checkbox.checked = this.element.elements.status.value === 'pending'
      this.remote = error.data?.task
      notice(this.element, `${error.message}${this.remote ? ` Versão salva: ${this.remote.title} · ${this.remote.status} · ${this.remote.project_name}.` : ''}`)
      this.element.querySelector('[data-task-reapply]').hidden = this.remote ? !this.remote.editable : false
    } finally { this.pending = false; if (checkbox.isConnected) checkbox.disabled = this.remote?.editable === false }
  }
  reapply() {
    if (this.remote) this.element.elements.version.value = this.remote.lock_version
    this.element.requestSubmit()
  }
}
