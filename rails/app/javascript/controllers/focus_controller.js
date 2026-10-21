import { Controller } from '@hotwired/stimulus'
import { sharedFocus, focusRequest, encodeUid } from 'controllers/focus_client'
import { paintFocus, primaryAction, visualTime } from 'controllers/focus_presenter'

export default class extends Controller {
  static values = { user: String, catalog: Object }
  static targets = ['surface', 'transport', 'message', 'retry', 'dialog', 'dialogTitle', 'dialogDescription', 'dialogConfirm', 'dialogFeedback']

  connect() {
    this.client = sharedFocus(this.userValue)
    this.client.confirmed = false
    this.unsubscribe = this.client.subscribe(() => this.paint())
    this.visible = () => {
      clearInterval(this.poll)
      if (document.visibilityState === 'visible') {
        this.client.confirmed = false
        this.client.read()
        this.poll = setInterval(() => this.client.read(), 15000)
      }
      this.paint()
    }
    this.online = () => this.visible()
    this.beforeCache = () => this.closeDialog()
    document.addEventListener('visibilitychange', this.visible)
    document.addEventListener('turbo:before-cache', this.beforeCache)
    window.addEventListener('online', this.online)
    this.tick = setInterval(() => this.paint(), 1000)
    const appearance = window.Stimulus.getControllerForElementAndIdentifier(this.element.closest('[data-controller~=studio]'), 'studio')
    const connection = this.connection = (this.connection || 0) + 1
    Promise.resolve(appearance?.saveQueue).then(() => {
      if (this.element.isConnected && this.connection === connection) this.visible()
    })
  }
  disconnect() {
    this.connection = (this.connection || 0) + 1
    clearInterval(this.tick); clearInterval(this.poll)
    document.removeEventListener('visibilitychange', this.visible)
    document.removeEventListener('turbo:before-cache', this.beforeCache)
    window.removeEventListener('online', this.online)
    this.unsubscribe?.()
    this.closeDialog()
  }
  surfaceTargetConnected() { if (this.client) this.paint() }
  paint() { if (this.element.isConnected) paintFocus(this) }
  reconnect() { this.client.read() }
  async retry() {
    const envelope = this.client.pending
    if (envelope && await this.client.execute(envelope)) this.advancePreference(envelope.preferenceBefore)
  }
  dismiss() { if (!this.client.pending) { this.client.message = ''; this.paint() } }
  advancePreference(previous) {
    const appearance = window.Stimulus.getControllerForElementAndIdentifier(this.element.closest('[data-controller~=studio]'), 'studio')
    const current = this.client.snapshot?.preference_version
    if (Number.isInteger(previous) && current === previous + 1 && appearance.version === previous && !appearance.pending && !appearance.failed) appearance.version = current
  }
  sessionContext() {
    const session = this.client.snapshot?.session, context = {}
    if (!session) return context
    const project = this.catalogValue.projects.find(p => p.uid === session.project_uid)
    const task = this.catalogValue.tasks.find(t => t.uid === session.task_uid)
    // Missing/stale hints are never replaced by a different context.
    if (session.project_uid) { context.project_uid = encodeUid(session.project_uid); context.project_version = project?.version }
    if (session.task_uid) { context.task_uid = encodeUid(session.task_uid); context.task_version = task?.version }
    return context
  }
  contextLabel(session) {
    if (!session) return 'Um único Pomodoro em todas as telas.'
    const project = this.catalogValue.projects.find(p => p.uid === session.project_uid)
    const task = this.catalogValue.tasks.find(t => t.uid === session.task_uid)
    return [task?.name || (session.task_uid ? 'Tarefa vinculada' : ''), project?.name || (session.project_uid ? 'Projeto vinculado' : '')].filter(Boolean).join(' · ') || 'Foco global · sem tarefa'
  }
  get blocked() { return this.preparing || this.client.pending || this.client.sending || !this.client.confirmed || !Number.isInteger(this.client.snapshot?.preference_version) }
  async create(context) {
    if (this.blocked) return
    if (this.client.snapshot?.session) { this.existing(); return }
    this.preparing = true; this.paint()
    try {
      const data = await focusRequest('/focus/intents', { context }, 'POST')
      await this.client.execute({ url: '/focus/prepare', body: { intent: data.intent, command_id: crypto.randomUUID(), version: 0, operation: 'start_new' }, success: 'Pomodoro iniciado.' })
    } catch (error) { this.client.message = error.message + (error.status === 409 ? '. Recarregue a página para conferir o contexto antes de tentar novamente.' : ''); await this.client.read() }
    finally { this.preparing = false; this.paint() }
  }
  startTask(event) { this.create(JSON.parse(event.currentTarget.dataset.focusContext)) }
  primary(event) {
    if (this.blocked) return
    const action = primaryAction(this.client, visualTime(this.client).remaining).action
    if (action === 'start_new') this.create(JSON.parse(event.currentTarget.closest('[data-focus-context]').dataset.focusContext))
    else if (action === 'confirm') this.openDialog('Concluir sessão?', 'Confirme apenas o período conferido. A tarefa associada permanecerá como está.', () => this.command('confirm'), event.currentTarget)
    else if (action) this.command(action)
  }
  command(action, parameters = {}, expected = this.client.snapshot?.session) {
    if (this.blocked) return
    const session = expected
    if (!session) return
    const kind = { start: 'start', resume: 'start', pause: 'pause', reconcile: 'pause', resolve: 'pause', restart: 'reset', cancel: 'reset', confirm: 'complete' }[action]
    return this.client.execute({ preferenceBefore: parameters.preference_version, url: `/focus/${encodeUid(session.uid)}/commands`, body: {
      command_id: crypto.randomUUID(), version: session.version, kind, parameters: { action, ...parameters }
    }, success: action === 'confirm' ? 'Sessão concluída. Sua tarefa não foi alterada.' : 'Ação confirmada.' }).then(accepted => { if (accepted) this.advancePreference(parameters.preference_version) })
  }
  resolve(event) {
    if (this.blocked) return
    const recovery = this.client.snapshot?.recovery
    if (recovery) this.command('resolve', { recovery_id: recovery.receipt_id, decision: event.currentTarget.dataset.focusResolve })
  }
  reset(event) {
    if (this.blocked || !this.client.snapshot?.session) return
    this.openReset(this.client.snapshot.session.duration_seconds, false, event.currentTarget)
  }
  openReset(duration, changePreference, trigger) {
    const expected = structuredClone(this.client.snapshot.session), preferenceVersion = this.client.snapshot.preference_version, context = this.sessionContext()
    this.openDialog('Reiniciar Pomodoro?', 'A tentativa atual será preservada como cancelada. Uma nova sessão ficará pronta, sem iniciar automaticamente e mantendo o contexto. Se a tarefa mudou de projeto, cancele e inicie novamente a partir dela.', async () => {
      try {
        const intent = await focusRequest('/focus/intents', { context, duration_seconds: duration }, 'POST')
        await this.command('restart', { intent: intent.intent, ...(changePreference ? { preference_version: preferenceVersion } : {}) }, expected)
      } catch (error) { this.client.message = error.message + (error.status === 409 ? '. Recarregue a página para conferir o contexto antes de tentar novamente.' : ''); await this.client.read() }
    }, trigger)
  }
  cancel(event) {
    if (this.blocked) return
    this.openDialog('Cancelar sessão?', 'A tentativa e os checkpoints serão preservados, sem registrar uma sessão concluída.', () => this.command('cancel'), event.currentTarget)
  }
  preset(event) {
    if (this.blocked) return
    const snapshot = this.client.snapshot, duration = (snapshot.session?.duration_seconds || snapshot.preset_seconds) === 1500 ? 2700 : 1500
    if (snapshot.session?.status === 'ready') { this.openReset(duration, true, event.currentTarget); return }
    if (snapshot.session) { this.client.message = 'Encerre ou cancele a sessão antes de mudar o preset. A duração em andamento foi preservada.'; this.paint(); return }
    this.openDialog(`Usar ${duration / 60} minutos?`, 'Este preset será usado nos próximos inícios. A aparência e os demais ajustes serão preservados.', () => this.client.execute({
      url: '/focus/preset', method: 'PATCH', preferenceBefore: snapshot.preference_version, body: { duration_seconds: duration, version: snapshot.preference_version }, success: 'Preset salvo. Outras preferências foram preservadas.'
    }).then(accepted => { if (accepted) this.advancePreference(snapshot.preference_version) }), event.currentTarget)
  }
  existing() {
    this.client.message = 'Já existe um Pomodoro global. Abra Foco para conferir, pausar ou cancelar; o contexto atual foi preservado.'
    this.paint()
  }
  openDialog(title, description, operation, trigger) {
    this.dialogVersion = { uid: this.client.snapshot?.session?.uid, version: this.client.snapshot?.session?.version, preference: this.client.snapshot?.preference_version }
    this.dialogTitleTarget.textContent = title
    this.dialogDescriptionTarget.textContent = description
    this.dialogFeedbackTarget.textContent = ''
    this.operation = operation; this.returnTo = trigger
    this.dialogTarget.showModal()
    this.dialogTarget.querySelector('[autofocus]').focus()
  }
  async confirmDialog() {
    if (this.blocked || this.dialogPending) return
    const session = this.client.snapshot?.session, opened = this.dialogVersion
    if (session?.uid !== opened.uid || session?.version !== opened.version || this.client.snapshot.preference_version !== opened.preference) {
      this.client.message = 'O estado mudou em outra aba. Feche e confira antes de decidir novamente.'; this.paint(); return
    }
    this.dialogPending = true; this.dialogConfirmTarget.disabled = true
    try { await this.operation() }
    finally {
      this.dialogPending = false; this.dialogConfirmTarget.disabled = false
      this.closeDialog()
    }
  }
  closeDialog(event) {
    event?.preventDefault()
    if (!this.dialogPending && this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }
  returnFocus() {
    const active = document.activeElement
    // Native close already restores focus. A queued close event must not undo
    // a subsequent keyboard action or steal focus from another open dialog.
    if (!this.element.isConnected || this.element.querySelector('dialog[open]') ||
        (active && active !== document.body && !this.dialogTarget.contains(active))) return
    const target = this.returnTo?.isConnected && !this.returnTo.disabled && this.returnTo.getClientRects().length ? this.returnTo : this.element.querySelector('[data-focus-primary]:not(:disabled)') || this.element.querySelector('main h1')
    target?.focus({ preventScroll: true })
  }
  dialogKeys(event) {
    if (event.key !== 'Tab') return
    const controls = [...this.dialogTarget.querySelectorAll('button:not(:disabled), a[href]')].filter(el => el.getClientRects().length)
    const first = controls[0], last = controls.at(-1)
    if ((event.shiftKey && document.activeElement === first) || (!event.shiftKey && document.activeElement === last)) {
      event.preventDefault(); (event.shiftKey ? last : first)?.focus()
    }
  }
}
