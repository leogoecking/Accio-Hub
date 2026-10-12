import { Controller } from '@hotwired/stimulus'
let tabFocus = null

export default class extends Controller {
  connect() {
    if (tabFocus) { const id = tabFocus; tabFocus = null; requestAnimationFrame(() => document.getElementById(id)?.focus({ preventScroll: true })) }
  }
  remember(event) {
    const tab = event.target.closest('[data-project-tab]')
    if (tab) tabFocus = tab.id
  }
  keys(event) {
    if (!event.target.matches('[data-project-tab]') || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
    event.preventDefault()
    const tabs = Array.from(this.element.querySelectorAll('[data-project-tab]')), index = tabs.indexOf(event.target)
    const next = tabs[event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length]
    next.click()
  }
}
