import { Controller } from '@hotwired/stimulus'
import { request, refresh, notice, restoreFocus } from "controllers/project_ui"

export default class extends Controller {
  async submit(event) {
    event.preventDefault()
    if (this.pending) return
    const button = this.element.querySelector('[type=submit]'), id = button.id
    this.pending = true; button.disabled = true
    try {
      const result = await request(this.element.action, new FormData(this.element))
      await refresh(); restoreFocus(id); notice(document.querySelector('#project-surface'), result.message)
    } catch (error) {
      notice(this.element, error.message)
      this.remote = error.data?.project
      const operation = this.element.elements.namedItem('operation').value
      this.element.querySelector('[data-project-reapply]').hidden = !this.remote || (this.remote.status === 'archived' && operation !== 'restore')
      if (this.remote) notice(this.element, `${error.message} Versão atual: ${this.remote.name} · ${this.remote.status}.`)
    } finally { this.pending = false; if (button.isConnected) button.disabled = false }
  }
  reapply() {
    this.element.elements.namedItem('version').value = this.remote.lock_version
    this.element.requestSubmit()
  }
}
