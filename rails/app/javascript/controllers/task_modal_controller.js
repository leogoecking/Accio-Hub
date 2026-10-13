import { Controller } from '@hotwired/stimulus'
export default class extends Controller {
  connect() {
    this.capture = event => { const opener = event.target.closest('[data-task-opener]'); if (opener) this.element.dataset.returnId = opener.id }
    document.addEventListener('click', this.capture)
  }
  disconnect() { document.removeEventListener('click', this.capture) }
}
