// Preserve the approved dark ink when readable; adapt only for darker accents.
export function actionInk(hex) {
  const luminance = color => {
    const c = color.match(/[a-f0-9]{2}/gi).map(value => parseInt(value, 16) / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
    return c[0] * .2126 + c[1] * .7152 + c[2] * .0722
  }
  if (!/^#[a-f0-9]{6}$/i.test(hex)) return '#10201c'
  const background = luminance(hex), original = luminance('#10201c')
  if ((Math.max(background, original) + .05) / (Math.min(background, original) + .05) >= 4.5) return '#10201c'
  return 1.05 / (background + .05) >= 4.5 ? '#ffffff' : '#000000'
}

export const formatTime = seconds => `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`

export function visualTime(client) {
  const snapshot = client.snapshot, session = snapshot?.session
  const duration = session?.duration_seconds || snapshot?.preset_seconds || 1500
  const elapsed = snapshot?.timing?.nominal_seconds || 0
  const interpolated = session?.status === 'running' && client.confirmed && document.visibilityState === 'visible'
    ? Math.max(0, (performance.now() - client.observedAt) / 1000) : 0
  return { duration, remaining: Math.max(0, duration - elapsed - interpolated) }
}

export function primaryAction(client, remaining) {
  const state = client.snapshot?.session?.status
  if (state === 'running') return remaining <= 0 || client.snapshot.timing.continuity === 'unknown'
    ? { action: 'reconcile', label: 'Conferir intervalo', glyph: '✓', state: remaining <= 0 ? 'Conclusão pendente' : 'Intervalo a conferir' }
    : { action: 'pause', label: 'Pausar Pomodoro', glyph: 'Ⅱ', state: 'Em andamento' }
  if (client.snapshot?.recovery) return { action: null, label: 'Resolva o intervalo abaixo', glyph: '…', state: 'Recuperação pendente' }
  if (state === 'awaiting_confirmation') return { action: 'confirm', label: 'Confirmar conclusão', glyph: '✓', state: 'Conclusão pendente' }
  if (state === 'paused') return { action: 'resume', label: 'Retomar Pomodoro', glyph: '▶', state: 'Pausado' }
  return { action: state === 'ready' ? 'start' : 'start_new', label: 'Iniciar Pomodoro', glyph: '▶', state: 'Pronto para começar' }
}

export function paintFocus(controller) {
  const client = controller.client, snapshot = client.snapshot, session = snapshot?.session
  controller.element.style.setProperty('--focus-action-ink', actionInk(getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()))
  const { duration, remaining } = visualTime(client)
  const primary = primaryAction(client, remaining)
  const busy = !!(client.sending || client.pending || controller.recoveryFlow?.busy || controller.presetFlow?.busy || controller.preparing || !client.confirmed || !Number.isInteger(snapshot?.preference_version))
  controller.surfaceTargets.forEach(surface => {
    surface.querySelector('[data-focus-clock]').textContent = snapshot ? formatTime(Math.ceil(remaining)) : '--:--'
    surface.querySelector('[data-focus-dial]').style.setProperty('--p', `${100 * (1 - remaining / duration)}%`)
    surface.querySelector('[data-focus-state]').textContent = snapshot ? primary.state : 'Consultando servidor'
    surface.querySelector('[data-focus-context-label]').textContent = controller.contextLabel(session)
    const button = surface.querySelector('[data-focus-primary]')
    button.disabled = busy || !primary.action || (!session && surface.dataset.focusArchived === 'true')
    button.setAttribute('aria-label', primary.label); button.title = primary.label
    const icon = surface.querySelector('[data-focus-icon]')
    if (icon.dataset.glyph !== primary.glyph) {
      const paths = { '▶': 'm8 5 11 7-11 7V5Z', 'Ⅱ': 'M8 5v14M16 5v14', '✓': 'm5 12 4 4L19 6', '…': 'M5 12h1m5 0h1m5 0h1' }
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      for (const [name, value] of Object.entries({ width: '20', height: '20', viewBox: '0 0 24 24', 'aria-hidden': 'true', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.7', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) svg.setAttribute(name, value)
      const path = document.createElementNS(svg.namespaceURI, 'path'); path.setAttribute('d', paths[primary.glyph]); svg.append(path)
      icon.replaceChildren(svg); icon.dataset.glyph = primary.glyph
    }
    surface.querySelector('[data-focus-reset]').disabled = busy || !session
    const preset = surface.querySelector('[data-focus-preset]')
    preset.disabled = busy
    preset.textContent = `${duration / 60}m`
    preset.setAttribute('aria-label', `Preset de ${duration / 60} minutos. Selecionar 25 ou 45 minutos`)
    const cancel = surface.querySelector('[data-focus-cancel]')
    cancel.hidden = !session; cancel.disabled = busy
    const feedback = surface.querySelector('[data-focus-feedback]')
    const message = !client.confirmed ? 'Estado ainda não confirmado pelo servidor.' : snapshot?.timing?.continuity === 'unknown' ? 'Continuidade incerta. Confira o intervalo antes de retomar ou concluir.' : client.message || ''
    if (feedback.textContent !== message) feedback.textContent = message // Never announce every clock tick.
    surface.querySelector('[data-focus-recovery]').hidden = !snapshot?.recovery
    if (snapshot?.recovery) {
      const recovery = snapshot.recovery
      surface.querySelector('[data-focus-checkpoint]').textContent = `Tempo confirmado: ${formatTime(recovery.checkpoint_seconds)}.`
      surface.querySelector('[data-focus-estimate]').textContent = recovery.candidate_seconds == null ? 'Não há estimativa válida para este intervalo.' : `Estimativa disponível do servidor: ${formatTime(recovery.candidate_seconds)}.`
      surface.querySelectorAll('[data-focus-resolve]').forEach(el => {
        if (el.dataset.focusResolve === 'accept_estimate') el.textContent = recovery.candidate_seconds === session.duration_seconds ? 'Aceitar estimativa e revisar conclusão' : 'Aceitar estimativa e continuar'
        el.disabled = busy || (el.dataset.focusResolve === 'accept_estimate' && recovery.candidate_seconds == null)
      })
    }
  })
  const visibleSurface = controller.surfaceTargets.some(surface => { const rect = surface.getBoundingClientRect(); return surface.getClientRects().length && rect.bottom > 0 && rect.top < innerHeight })
  controller.transportTarget.hidden = !client.pending && (visibleSurface || !client.message)
  if (controller.messageTarget.textContent !== (client.message || '')) controller.messageTarget.textContent = client.message || ''
  controller.retryTarget.hidden = !client.pending
  controller.retryTarget.disabled = client.sending
  if (controller.dialogTarget.open) controller.dialogFeedbackTarget.textContent = client.message || ''
}
