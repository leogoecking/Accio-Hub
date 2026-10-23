import { Controller } from '@hotwired/stimulus'
export default class extends Controller {
  disconnect() { clearTimeout(this.timer); this.sequence = (this.sequence || 0) + 1 }
  search() {
    clearTimeout(this.timer)
    this.element.closest('dialog').querySelector('[data-search-empty]').setAttribute('aria-busy', 'true')
    const sequence = this.sequence = (this.sequence || 0) + 1
    this.timer = setTimeout(async () => {
      try {
        const response = await fetch('/tasks/search?q=' + encodeURIComponent(this.element.value), {headers:{Accept:'text/html'}, credentials:'same-origin'})
        if (!response.ok) return
        const html = await response.text()
        if (!this.element.isConnected || sequence !== this.sequence) return
        const dialog = this.element.closest('dialog')
        dialog.querySelector('[data-task-search-results]').innerHTML = html
        dialog.querySelector('[data-search-empty]').hidden = !!dialog.querySelector('[data-task-search-results] a') || Array.from(dialog.querySelectorAll('[data-search-result]')).some(el => !el.hidden)
      } catch { /* App navigation still works when the task search cannot reach Rails. */ }
      finally {
        if (this.element.isConnected && sequence === this.sequence) this.element.closest('dialog').querySelector('[data-search-empty]').setAttribute('aria-busy', 'false')
      }
    }, 180)
  }
}
