import { Controller } from '@hotwired/stimulus'
import { studio, request, refresh, notice, restoreFocus } from "controllers/project_ui"

export default class extends Controller {
  connect() {
    this.appearance = studio(this.element)
  }
  disconnect() { clearTimeout(this.searchTimer) }
  scheduleSearch(event) {
    if (event.target.id !== "project-search") return
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.runSearch(), 250)
  }
  async search(event) {
    if (!event.target.matches(".project-search")) return
    event.preventDefault()
    clearTimeout(this.searchTimer)
    await this.runSearch()
  }
  async runSearch() {
    const sequence = this.searchSequence = (this.searchSequence || 0) + 1
    const value = this.element.querySelector('#project-search').value
    const url = new URL(window.location.href); value ? url.searchParams.set('q', value) : url.searchParams.delete('q')
    try {
      const applied = await refresh(url, 'project-results', () => this.element.isConnected && sequence === this.searchSequence)
      if (applied) history.replaceState(history.state, '', url)
    } catch (error) { notice(this.element, error.message) }
  }
  filter(event) {
    if (event.target.matches('[data-filter]')) this.save({ [event.target.dataset.filter]: event.target.value }, event.target.id)
  }
  click(event) {
    const status = event.target.closest('[data-filter-status]')
    const favorite = event.target.closest('[data-filter-favorites]')
    if (status) this.save({ project_library_status: status.dataset.filterStatus }, status.id)
    if (favorite) this.save({ project_library_favorites_only: favorite.getAttribute('aria-pressed') !== 'true' }, favorite.id)
  }
  async save(filters, id, version) {
    if (this.pending) return
    this.pending = true
    await this.appearance.saveQueue
    if (!this.appearance.initialized || this.appearance.failed) { this.pending = false; notice(this.element, 'Resolva as preferências pendentes antes de filtrar.'); return }
    try {
      const result = await request('/projects/filters', { filters, version: version ?? this.appearance.version }, 'PATCH')
      if (!this.appearance.pending && !this.appearance.failed && this.appearance.version <= result.version) {
        this.appearance.version = result.version
        this.appearance.confirmed = structuredClone(result.appearance)
        this.appearance.preferences = structuredClone(result.appearance)
        this.appearance.paint()
      }
      await refresh(); restoreFocus(id)
    } catch (error) {
      notice(this.element, error.message)
      if (error.data?.version !== undefined) {
        this.retry = { filters, id, version: error.data.version }
        const button = document.createElement('button'); button.className = 'button tertiary'; button.textContent = 'Reaplicar filtro sobre a versão confirmada'
        button.addEventListener('click', () => this.save(this.retry.filters, this.retry.id, this.retry.version), { once: true })
        this.element.querySelector('[data-project-notice]').append(button)
        // Appearance must retain its own local draft; filters update only their three fields.
      }
    } finally { this.pending = false }
  }
}
