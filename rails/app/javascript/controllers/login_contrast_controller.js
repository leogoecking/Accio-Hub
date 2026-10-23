import { Controller } from '@hotwired/stimulus'
import { actionInk } from 'controllers/focus_presenter'

export default class extends Controller {
  connect() {
    const root = document.documentElement
    root.style.setProperty('--accent-action-ink', actionInk(getComputedStyle(root).getPropertyValue('--accent').trim()))
  }
}
