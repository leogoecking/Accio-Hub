import { Controller } from '@hotwired/stimulus'
import { request, refresh, notice, restoreFocus } from "controllers/project_ui"

export default class extends Controller {
  connect() {
    this.frame = this.element.closest('turbo-frame')
    this.returnId = this.frame.dataset.returnId
    this.form = this.element.querySelector('form')
    this.element.showModal()
    ;(this.form?.querySelector('#project-name') || this.element.querySelector('button')).focus()
    this.dirty = false
    this.navigation = event => { if (this.dirty || this.pending) { event.preventDefault(); notice(this.element, 'Salve ou cancele este formulário antes de navegar.') } }
    document.addEventListener('turbo:before-visit', this.navigation)
    document.addEventListener('turbo:before-render', this.navigation)
  }
  disconnect() {
    document.removeEventListener('turbo:before-visit', this.navigation)
    document.removeEventListener('turbo:before-render', this.navigation)
  }
  preview(event) {
    this.dirty = true
    const preview = this.element.querySelector('#project-preview')
    preview.querySelector('[data-preview-name]').textContent = this.form.querySelector('#project-name').value || 'Seu próximo projeto'
    if (event.target.matches('#project-color, #project-color-hex') && /^#[0-9a-f]{6}$/i.test(event.target.value)) {
      this.form.querySelector('#project-color').value = event.target.value
      this.form.querySelector('#project-color-hex').value = event.target.value
      this.form.querySelector('#project-color-value').value = event.target.value
      preview.style.setProperty('--project-color', event.target.value)
    }
    if (event.target.id === 'project-icon') {
      const icon = document.querySelector(`[data-project-icon-preview="${event.target.value}"]`)
      if (icon) preview.querySelector('.project-emblem').innerHTML = icon.innerHTML
    }
  }
  async submit(event) {
    event.preventDefault()
    if (this.pending || !this.form.reportValidity()) return
    this.pending = true; this.form.querySelector('[type=submit]').disabled = true
    try {
      const result = await request(this.form.action, new FormData(this.form))
      this.dirty = false
      await refresh()
      this.element.close()
      this.afterClose()
      notice(document.querySelector('#project-surface'), result.message)
      if (result.project?.path) {
        const feedback = document.querySelector('#project-surface [data-project-notice]')
        const link = document.createElement('a'); link.href = result.project.path; link.textContent = ' Abrir projeto'; link.className = 'quiet-link'
        feedback?.append(link)
      }
    } catch (error) {
      notice(this.element, error.message)
      this.remote = error.data?.project
      const remote = this.element.querySelector('[data-project-remote]')
      remote.hidden = !this.remote
      remote.textContent = this.remote ? `Versão salva: ${this.remote.name} · ${this.remote.status}. Descrição: ${this.remote.description || 'Sem descrição'}. Ícone: ${this.remote.icon}. Cor: ${this.remote.color || 'herdada'}.` : ''
      this.element.querySelector('[data-project-reapply]').hidden = !this.remote || this.remote.status === 'archived'
      this.element.querySelector('[data-project-reload]').hidden = !this.remote
    } finally {
      this.pending = false
      if (this.element.isConnected) this.form.querySelector('[type=submit]').disabled = false
    }
  }
  reapply() {
    this.form.querySelector('[name=version]').value = this.remote.lock_version
    this.form.requestSubmit()
  }
  reload() {
    for (const key of ['name', 'description', 'icon', 'color']) {
      const input = this.form.elements.namedItem(`project[${key}]`)
      if (input) input.value = this.remote[key] || ''
    }
    this.form.querySelector('[name=version]').value = this.remote.lock_version
    const color = this.remote.display_color
    if (color) { this.form.querySelector('#project-color').value = color; this.form.querySelector('#project-color-hex').value = color }
    const preview = this.element.querySelector('#project-preview')
    preview.querySelector('[data-preview-name]').textContent = this.remote.name
    preview.style.setProperty('--project-color', color)
    preview.querySelector('.project-emblem').innerHTML = this.element.querySelector(`[data-project-icon-preview="${this.remote.icon}"]`).innerHTML
    this.dirty = false
    this.form.querySelector('[type=submit]').disabled = this.remote.status === 'archived'
    this.element.querySelector('[data-project-reapply]').hidden = true
    notice(this.element, this.remote.status === 'archived' ? 'Projeto arquivado; feche o formulário e restaure na Biblioteca.' : 'Versão salva carregada. Você pode conferir e editar.')
    this.form.querySelector('#project-name').focus()
  }
  close() { if (!this.pending) this.element.close() }
  cancel(event) { event.preventDefault(); this.close() }
  afterClose() {
    if (this.frame.dataset.returnUrl) {
      history.replaceState(history.state, '', this.frame.dataset.returnUrl)
      delete this.frame.dataset.returnUrl
    }
    this.frame.removeAttribute('src')
    this.frame.innerHTML = ''
    restoreFocus(this.returnId)
  }
  keys(event) {
    if (event.key !== 'Tab') return
    const controls = Array.from(this.element.querySelectorAll('button, input, select, textarea, a[href]')).filter(el => !el.disabled && el.tabIndex >= 0 && el.getClientRects().length)
    const first = controls[0], last = controls.at(-1)
    if ((event.shiftKey && document.activeElement === first) || (!event.shiftKey && document.activeElement === last)) {
      event.preventDefault(); (event.shiftKey ? last : first)?.focus()
    }
  }
}
