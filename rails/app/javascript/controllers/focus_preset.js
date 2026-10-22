// Presentation/reconciliation only: PATCH retains C's compare-and-swap contract.
// No receipt, automatic reapply, browser persistence or focus-session command.
export class FocusPreset {
  constructor(client) {
    this.client = client
    client.subscribe(() => this.reconcile()) // One coordinator per shared client, including Turbo visits.
  }
  owns(envelope) { return !!envelope && envelope === this.operation?.envelope }
  async save(duration, version) {
    if (this.busy || this.client.pending || !this.client.confirmed ||
        ![1500, 2700].includes(duration) || !Number.isInteger(version)) return
    this.operation = { envelope: Object.freeze({
      url: '/focus/preset', method: 'PATCH', preferenceBefore: version,
      body: Object.freeze({ duration_seconds: duration, version }),
      success: `Resposta de sucesso confirmada: preset de ${duration / 60} min salvo.`
    }) }
    return this.run()
  }
  async retry() {
    if (!this.busy && this.owns(this.client.pending)) return this.run()
  }
  async run() {
    const operation = this.operation
    if (!operation || this.busy) return
    this.busy = true
    try {
      return await this.client.execute(operation.envelope, data => {
        const requested = operation.envelope.body
        if (data?.duration_seconds !== requested.duration_seconds || data.version !== requested.version + 1) {
          throw new Error('Resposta do preset incompatível; operação ainda não confirmada.')
        }
        operation.success = true
      }, error => {
        operation.failure = error.status === 409 ? 'conflict' : 'uncertain'
        return !error.status || error.status === 409 || error.status >= 500 || error.status === 401
      })
    } finally {
      this.busy = false
      this.client.notify()
    }
  }
  reconcile() {
    const operation = this.operation, client = this.client
    if (!operation || client.sending) return
    const requested = operation.envelope.body
    const snapshot = client.snapshot
    const readable = client.confirmed && [1500, 2700].includes(snapshot?.preset_seconds) &&
      Number.isInteger(snapshot.preference_version) && snapshot.preference_version >= requested.version
    if (!readable) {
      client.message = operation.success
        ? `Resposta de sucesso confirmada: ${requested.duration_seconds / 60} min salvos. A leitura do valor atual está indisponível; consulte novamente.`
        : `${operation.failure === 'conflict' ? 'Retentativa ou edição recebeu conflito HTTP 409.' : 'Resposta do preset não confirmada.'} Operação incerta. Valor atual ainda não confirmado; consulte novamente ou tente a mesma solicitação.`
      return
    }
    const current = snapshot.preset_seconds / 60, same = snapshot.preset_seconds === requested.duration_seconds
    client.message = operation.success
      ? `Resposta de sucesso confirmada: ${requested.duration_seconds / 60} min salvos. Preset atual confirmado no servidor: ${current} min.${same ? '' : ' O valor mudou depois; confira antes de decidir novamente.'}`
      : `${operation.failure === 'conflict' ? 'Conflito HTTP 409. ' : 'A resposta da tentativa não foi confirmada. '}Preset atual confirmado no servidor: ${current} min. ${same ? 'Corresponde ao solicitado, mas a autoria da alteração não foi comprovada.' : `Difere do solicitado (${requested.duration_seconds / 60} min). Conflito: faça uma nova escolha explícita para alterar.`}`
    if (this.owns(client.pending)) client.pending = null
    this.operation = null
  }
}
