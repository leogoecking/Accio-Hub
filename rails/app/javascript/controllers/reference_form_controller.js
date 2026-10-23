import ProjectFormController from 'controllers/project_form_controller'
import { request, notice, refresh } from 'controllers/project_ui'

// Reuse the D1 dialog lifecycle, navigation guard, keyboard trap and focus return.
export default class extends ProjectFormController {
  connect() { super.connect(); this.form?.querySelector('#reference-title').focus(); this.updateKind() }
  preview() { this.dirty = true; this.updateKind() }
  async submit(event) {
    event.preventDefault()
    if (this.pending || this.blocked || !this.form.reportValidity()) return
    const focused = document.activeElement
    this.pending = true; this.form.querySelector('[type=submit]').disabled = true
    try {
      const result = await request(this.form.action, new FormData(this.form))
      await refresh()
      this.dirty = false; this.element.close(); this.afterClose()
      notice(document.querySelector('#project-surface'), result.message)
    } catch (error) {
      notice(this.element, error.message)
      this.remote = error.data?.reference
      const remote = this.element.querySelector('[data-reference-remote]')
      remote.hidden = !this.remote
      remote.textContent = this.remote ? `Versão salva: ${this.remote.title} · ${this.remote.kind} · ${this.remote.url || 'Sem URL'}. Descrição: ${this.remote.description || 'Sem descrição'}.` : ''
      this.element.querySelector('[data-reference-reapply]').hidden = !this.remote?.editable || error.data?.reason === 'project_archived'
      this.element.querySelector('[data-reference-reload]').hidden = !this.remote
    } finally {
      this.pending = false
      if (this.element.isConnected) this.form.querySelector('[type=submit]').disabled = !!this.blocked
      this.restoreFormFocus(focused)
    }
  }
  reapply() { this.form.elements.version.value = this.remote.lock_version; this.form.requestSubmit() }
  reload() {
    for (const key of ['title', 'kind', 'url', 'description']) this.form.elements.namedItem(`reference[${key}]`).value = this.remote[key] || ''
    this.form.elements.version.value = this.remote.lock_version
    this.blocked = !this.remote.editable
    this.form.querySelector('[type=submit]').disabled = this.blocked
    this.element.querySelector('[data-reference-reapply]').hidden = true
    this.dirty = false; this.updateKind()
    notice(this.element, this.blocked ? 'Projeto arquivado; restaure antes de alterar a referência.' : 'Versão salva carregada. Confira os campos antes de editar.')
    this.form.querySelector('#reference-title').focus()
  }
  updateKind() { if (this.form) this.form.querySelector('#reference-url').required = this.form.querySelector('#reference-kind').value === 'link' }
}
