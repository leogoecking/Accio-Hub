import { encodeUid } from 'controllers/focus_client'

// Ephemeral UI orchestration. Each step keeps E1's separate transaction/receipt.
// A reload discards the continuation; SQLite alone retains the accepted time.
export class FocusRecovery {
  constructor(client, uuid = () => crypto.randomUUID()) {
    this.client = client
    this.uuid = uuid
  }
  owns(envelope) { return !!envelope && (envelope === this.operation?.resolve || envelope === this.operation?.resume) }
  async accept() {
    const { session, recovery } = this.client.snapshot || {}
    if (this.busy || this.client.pending || !this.client.confirmed || session?.status !== 'paused' ||
        !recovery || recovery.version !== session.version || !Number.isInteger(recovery.receipt_id) ||
        !Number.isInteger(recovery.candidate_seconds) || recovery.candidate_seconds < session.elapsed_seconds ||
        recovery.candidate_seconds > session.duration_seconds) return
    const command = (kind, action, version, parameters = {}) => Object.freeze({
      url: `/focus/${encodeUid(session.uid)}/commands`, body: Object.freeze({
        command_id: this.uuid(), version, kind, parameters: Object.freeze({ action, ...parameters })
      })
    })
    this.operation = {
      uid: session.uid, version: session.version, recoveryId: recovery.receipt_id,
      candidate: recovery.candidate_seconds, duration: session.duration_seconds, phase: 'resolve',
      resolve: command('pause', 'resolve', session.version, { recovery_id: recovery.receipt_id, decision: 'accept_estimate' }),
      resume: command('start', 'resume', session.version + 1)
    }
    return this.run()
  }
  async retry() {
    if (!this.busy && this.owns(this.client.pending)) return this.run()
  }
  validate(data, operation, phase) {
    const result = data?.result, session = result?.session
    const resolving = phase === 'resolve', envelope = operation[phase]
    const expectedStatus = resolving ? (operation.candidate === operation.duration ? 'awaiting_confirmation' : 'paused') : 'running'
    if (data?.command_id !== envelope.body.command_id || result?.focus_contract !== 1 ||
        !data.current || !Object.hasOwn(data.current, 'session') ||
        session?.uid !== operation.uid || session.version !== envelope.body.version + 1 ||
        session.status !== expectedStatus || session.duration_seconds !== operation.duration || session.elapsed_seconds !== operation.candidate || result.recovery !== null ||
        (resolving && (result.resolved_recovery_id !== operation.recoveryId || result.decision !== 'accept_estimate'))) {
      throw new Error('Resposta desta recuperação não confirmada. Tente novamente a mesma ação.')
    }
  }
  currentMatches(operation) {
    const session = this.client.snapshot?.session
    return this.client.confirmed && session?.uid === operation.uid && session.version === operation.version + 1 &&
      session.status === 'paused' && session.elapsed_seconds === operation.candidate && !this.client.snapshot.recovery
  }
  async run() {
    const operation = this.operation
    if (!operation || this.busy) return
    this.busy = true
    this.client.notify()
    try {
      if (operation.phase === 'resolve') {
        const accepted = await this.client.execute(operation.resolve, data => this.validate(data, operation, 'resolve'))
        if (!accepted) {
          if (!this.client.pending) this.operation = null
          return
        }
        if (operation.candidate === operation.duration) {
          this.client.message = 'Estimativa aceita e salva. Confira o estado atual e revise a conclusão; ela exige sua confirmação.'
          this.operation = null
          return
        }
        // The receipt above proves ownership. The fresh snapshot can only veto
        // continuation; it never supplies another operation's version.
        if (!this.currentMatches(operation)) {
          this.client.message = 'Estimativa aceita e salva. Retomada não solicitada: o estado mudou em outra aba ou ainda não foi confirmado. Atualize e confira antes de retomar.'
          this.operation = null
          return
        }
        operation.phase = 'resume'
      }
      const accepted = await this.client.execute(operation.resume, data => this.validate(data, operation, 'resume'))
      if (accepted) {
        const current = this.client.snapshot?.session
        this.client.message = current?.uid === operation.uid && current.version === operation.version + 2 && current.status === 'running'
          ? 'Estimativa aceita e salva. Retomada confirmada.'
          : 'Estimativa aceita e salva. A retomada foi confirmada nesta operação; confira o estado atual, que pode ter mudado em outra aba.'
        this.operation = null
      } else {
        this.client.message = `Estimativa aceita e salva. Retomada ${this.client.pending ? 'ainda não confirmada. Tente a mesma ação' : 'rejeitada. Confira o estado antes de tentar retomar'}: ${this.client.message}`
        if (!this.client.pending) this.operation = null
      }
    } finally {
      this.busy = false
      this.client.notify()
    }
  }
}
