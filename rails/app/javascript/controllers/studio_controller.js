import { Controller } from "@hotwired/stimulus"

let navigated = false

export default class extends Controller {
  static values = { appearance: Object, defaults: Object }

  connect() {
    this.preferences = structuredClone(this.appearanceValue)
    this.editing = false
    this.revision = 0
    this.pending = 0
    this.saveQueue = Promise.resolve()
    this.keyHandler = this.keydown.bind(this)
    this.visitHandler = this.beforeVisit.bind(this)
    document.addEventListener("keydown", this.keyHandler)
    document.addEventListener("turbo:before-visit", this.visitHandler)
    this.clock()
    this.interval = setInterval(() => this.clock(), 1000)
    this.paint()
    this.element.dataset.ready = "true"
    if (navigated) {
      navigated = false
      this.element.querySelector("main h1")?.setAttribute("tabindex", "-1")
      this.element.querySelector("main h1")?.focus({ preventScroll: true })
    }
  }

  disconnect() {
    clearInterval(this.interval)
    document.removeEventListener("keydown", this.keyHandler)
    document.removeEventListener("turbo:before-visit", this.visitHandler)
    this.element.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
  }

  all(selector) { return Array.from(this.element.querySelectorAll(selector)) }

  clock() {
    const now = new Date()
    this.all("[data-now-time]").forEach(el => { el.textContent = now.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) })
    this.all("[data-now-date]").forEach(el => { el.textContent = now.toLocaleDateString("pt-BR", { weekday: "long", day: "numeric", month: "long" }) })
  }

  click(event) {
    const el = event.target.closest("button, [data-route], [data-backdrop]")
    if (!el || !this.element.contains(el)) return
    if (el.matches("[data-backdrop]") && event.target === el) this.closeDialog()
    if (el.dataset.open) this.openDialog(el.dataset.open, el)
    if (el.hasAttribute("data-close")) this.closeDialog()
    if (el.dataset.demo) {
      this.showDemo(el)
    }
    if (el.dataset.route) {
      const path = this.element.querySelector(`.rail-icons a[href$='/${el.dataset.route}']`)?.getAttribute("href")
      if (path) window.Turbo.visit(path)
    }
    if (el.dataset.wallpaper) { this.preferences.wallpaper = el.dataset.wallpaper; this.save() }
    if (el.hasAttribute("data-music-expand")) { this.preferences.musicExpanded = !this.preferences.musicExpanded; this.save() }
    if (el.hasAttribute("data-edit")) { this.editing = !this.editing; this.paint() }
    if (el.dataset.order) this.move(el.dataset.order, el.dataset.id, Number(el.dataset.direction))
    if (el.dataset.zoom) {
      const widget = this.preferences.widgets.find(w => w.id === el.dataset.zoom)
      const spans = [3, 4, 5, 6, 8, 12]
      widget.span = spans[(spans.indexOf(widget.span) + 1) % spans.length]
      this.save()
    }
    if (el.hasAttribute("data-reset-widgets")) { this.preferences.widgets = structuredClone(this.defaultsValue.widgets); this.save() }
    if (el.hasAttribute("data-retry")) this.save()
  }

  change(event) {
    const el = event.target
    if (el.dataset.pref) this.preferences[el.dataset.pref] = el.type === "checkbox" ? el.checked : el.value
    else if (el.dataset.dockVisible) {
      this.preferences.dockHidden = this.preferences.dockHidden.filter(id => id !== el.dataset.dockVisible)
      if (!el.checked) this.preferences.dockHidden.push(el.dataset.dockVisible)
    } else if (el.dataset.visible) this.preferences.widgets.find(w => w.id === el.dataset.visible).visible = el.checked
    else if (el.dataset.span) this.preferences.widgets.find(w => w.id === el.dataset.span).span = Number(el.value)
    else return
    this.save()
  }

  move(kind, id, direction) {
    const array = kind === "dock" ? this.preferences.dockOrder : this.preferences.widgets
    const index = array.findIndex(item => (kind === "dock" ? item : item.id) === id)
    const target = index + direction
    if (index < 0 || target < 0 || target >= array.length) return
    ;[array[index], array[target]] = [array[target], array[index]]
    this.save()
  }

  paint() {
    const p = this.preferences
    document.documentElement.dataset.theme = p.theme
    document.documentElement.dataset.wallpaper = p.wallpaper
    document.documentElement.style.setProperty("--accent", p.accent)
    this.all("[data-pref]").forEach(el => { if (el.type === "checkbox") el.checked = p[el.dataset.pref]; else el.value = p[el.dataset.pref] })
    this.all("[data-wallpaper]").forEach(el => { const selected = el.dataset.wallpaper === p.wallpaper; el.classList.toggle("active", selected); el.setAttribute("aria-pressed", String(selected)) })
    this.all(".music-zone").forEach(el => { el.hidden = !p.music })
    this.all(".music-expanded").forEach(el => { el.hidden = !p.musicExpanded })
    this.all("[data-music-expand]").forEach(el => { el.setAttribute("aria-expanded", String(p.musicExpanded)); if (el.classList.contains("music-button")) el.setAttribute("aria-label", p.musicExpanded ? "Recolher player" : "Expandir player") })
    this.all("[data-edit]").forEach(el => { el.classList.toggle("selected", this.editing); el.setAttribute("aria-pressed", String(this.editing)) })
    this.all("[data-edit-label]").forEach(el => { el.textContent = this.editing ? "Concluir edição" : "Organizar board" })
    this.all("[data-widget-action]").forEach(el => { el.hidden = this.editing })
    this.all("[data-zoom], [data-handle]").forEach(el => { el.hidden = !this.editing })
    p.dockOrder.forEach(id => this.all(`[data-dock='${id}']`).forEach(el => { el.hidden = p.dockHidden.includes(id); el.draggable = this.editing; el.classList.toggle("dock-edit", this.editing); el.parentElement.append(el) }))
    p.widgets.forEach(w => this.all(`[data-widget='${w.id}']`).forEach(el => { el.className = `panel panel-${w.id} span-${w.span}${this.editing ? " editing" : ""}`; el.hidden = !w.visible; el.draggable = this.editing; el.parentElement.append(el) }))
    this.all("[data-dock-visible]").forEach(el => { el.checked = !p.dockHidden.includes(el.dataset.dockVisible) })
    this.all("[data-visible]").forEach(el => { el.checked = p.widgets.find(w => w.id === el.dataset.visible).visible })
    this.all("[data-span]").forEach(el => { el.value = p.widgets.find(w => w.id === el.dataset.span).span })
    for (const kind of ["dock", "widgets"]) {
      const ids = kind === "dock" ? p.dockOrder : p.widgets.map(w => w.id)
      ids.forEach(id => this.all(`[data-${kind === "dock" ? "dock" : "widget"}-row='${id}']`).forEach(el => { el.parentElement.append(el) }))
      this.all(`[data-order='${kind}']`).forEach(el => { const i = ids.indexOf(el.dataset.id); el.disabled = i + Number(el.dataset.direction) < 0 || i + Number(el.dataset.direction) >= ids.length })
    }
    // Moving a focused node in the DOM can drop focus, especially in Firefox.
    if (this.focusAfterPaint?.isConnected) {
      const target = this.focusAfterPaint.disabled
        ? this.focusAfterPaint.parentElement.querySelector("button:not([disabled])")
        : this.focusAfterPaint
      target?.focus({ preventScroll: true })
    }
  }

  save() {
    this.focusAfterPaint = document.activeElement
    this.paint()
    this.focusAfterPaint = null
    const snapshot = structuredClone(this.preferences)
    const revision = ++this.revision
    this.pending++
    this.status("Salvando preferências…", false)
    this.saveQueue = this.saveQueue.then(async () => {
      try {
        const response = await fetch("/appearance", { method: "PATCH", headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content }, body: JSON.stringify({ appearance: snapshot }) })
        if (!response.ok) throw new Error("save failed")
        const data = await response.json()
        if (revision === this.revision) {
          this.preferences = data.appearance
          this.focusAfterPaint = document.activeElement
          this.paint()
          this.focusAfterPaint = null
          this.failed = false
          this.status("Preferências salvas neste navegador.", false)
        }
      } catch {
        this.failed = true
        this.status("Alterações de aparência ainda não salvas. Tente novamente.", true)
      } finally {
        this.pending--
        if (!this.pending && !this.failed) this.element.querySelector("[data-save-status]").hidden = true
      }
    })
    return this.saveQueue
  }

  status(message, retry) {
    const container = this.element.querySelector("dialog[open]") || this.element
    container.append(this.element.querySelector("[data-save-status]"))
    this.element.querySelector("[data-save-message]").textContent = message
    this.element.querySelector("[data-save-status]").hidden = false
    this.element.querySelector("[data-retry]").hidden = !retry
  }

  beforeVisit(event) {
    if (this.pending || this.failed) {
      event.preventDefault()
      if (!this.pending) { this.status("Salve as preferências pendentes antes de navegar.", true); return }
      const url = event.detail.url
      this.saveQueue.then(() => { if (!this.failed && this.element.isConnected) window.Turbo.visit(url) })
      return
    }
    this.closeDialog()
    navigated = true
  }

  openDialog(id, trigger) {
    this.closeDialog()
    const dialog = this.element.querySelector(`#${id}`)
    if (!dialog) return
    dialog.returnFocus = trigger || document.activeElement
    dialog.showModal()
    dialog.append(this.element.querySelector("[data-save-status]"))
    if (id === "search") { const input = dialog.querySelector("input"); input.value = ""; this.search({ target: input }); input.focus() }
    else dialog.querySelector("button, input, select")?.focus()
  }

  showDemo(trigger) {
    const descriptions = {
      capture: "Captura rápida e edição de tarefas/notas serão transportadas nas próximas etapas. Nenhum conteúdo é gravado nesta demonstração.",
      focus: "O Pomodoro está apresentado como referência visual. Sessões funcionais e persistidas serão entregues na P1.2.",
      music: "Accio Music é uma barra global demonstrativa. A reprodução de áudio permanece planejada."
    }
    this.element.querySelector("[data-demo-message]").textContent = descriptions[trigger.dataset.demo] || descriptions.capture
    this.openDialog("demo", trigger)
  }

  closeDialog() {
    this.element.querySelectorAll("dialog[open]").forEach(dialog => {
      dialog.close()
      this.afterClose({ target: dialog })
    })
  }
  cancel(event) { event.preventDefault(); this.closeDialog() }
  afterClose(event) {
    const container = this.element.querySelector("dialog[open]") || this.element
    container.append(this.element.querySelector("[data-save-status]"))
    // A queued close event must not steal focus from a dialog opened next.
    if (!this.element.querySelector("dialog[open]") && event.target.returnFocus?.isConnected) event.target.returnFocus.focus({ preventScroll: true })
  }

  keydown(event) {
    const dialog = this.element.querySelector("dialog[open]")
    if (event.key === "Tab" && dialog) {
      const controls = Array.from(dialog.querySelectorAll("a[href], button, input, select, textarea, [tabindex]"))
        .filter(el => !el.disabled && el.tabIndex >= 0 && el.getClientRects().length > 0)
      const first = controls[0]
      const last = controls[controls.length - 1]
      if (first && ((event.shiftKey && document.activeElement === first) || (!event.shiftKey && document.activeElement === last) || !dialog.contains(document.activeElement))) {
        event.preventDefault()
        ;(event.shiftKey ? last : first).focus()
      }
    }
    if (event.key === "Escape" && this.element.querySelector("dialog[open]")) {
      event.preventDefault()
      this.closeDialog()
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") { event.preventDefault(); this.openDialog("search", this.element.querySelector("[data-open=search]")) }
    if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key.toLowerCase() === "n") { event.preventDefault(); this.showDemo(this.element.querySelector("[data-demo=capture]")) }
  }

  search(event) {
    const normalize = s => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    const query = normalize(event.target.value.trim())
    this.all("[data-search-result]").forEach(el => { el.hidden = !normalize(el.dataset.searchResult).includes(query) })
    this.element.querySelector("[data-search-empty]").hidden = this.all("[data-search-result]").some(el => !el.hidden)
  }

  searchKeys(event) {
    if (event.key === "ArrowDown") { event.preventDefault(); this.all("[data-search-result]").find(el => !el.hidden)?.focus() }
    if (event.key === "Enter") { event.preventDefault(); this.all("[data-search-result]").find(el => !el.hidden)?.click() }
  }

  dragStart(event) {
    const el = event.target.closest("[data-dock], [data-widget]")
    if (!this.editing || !el) { event.preventDefault(); return }
    this.dragged = { kind: el.dataset.dock ? "dock" : "widgets", id: el.dataset.dock || el.dataset.widget }
    event.dataTransfer.setData("text/plain", this.dragged.id)
    event.dataTransfer.effectAllowed = "move"
  }
  dragOver(event) { if (this.dragged && event.target.closest("[data-dock], [data-widget]")) event.preventDefault() }
  drop(event) {
    const target = event.target.closest("[data-dock], [data-widget]")
    if (!this.dragged || !target) return
    event.preventDefault()
    const kind = target.dataset.dock ? "dock" : "widgets"
    if (kind !== this.dragged.kind) return
    const id = target.dataset.dock || target.dataset.widget
    const array = kind === "dock" ? this.preferences.dockOrder : this.preferences.widgets
    const from = array.findIndex(x => (kind === "dock" ? x : x.id) === this.dragged.id)
    const to = array.findIndex(x => (kind === "dock" ? x : x.id) === id)
    if (from >= 0 && to >= 0 && from !== to) { array.splice(to, 0, array.splice(from, 1)[0]); this.save() }
    this.dragged = null
  }
  dragEnd() { this.dragged = null }
}
