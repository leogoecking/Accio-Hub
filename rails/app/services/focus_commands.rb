class FocusCommands
  class Conflict < StandardError; end
  class Invalid < StandardError; end
  ACTIONS = { "start" => %w[prepare start_new start resume], "pause" => %w[pause reconcile resolve],
    "reset" => %w[restart cancel], "complete" => %w[confirm] }.freeze
  CONTEXT_FIELDS = %w[project_uid project_version task_uid task_version].freeze

  def initialize(user, time: FocusTime.new)
    @user = user
    @time = time
  end

  # Signed creation intentions reuse D1/D2's identity mechanism. These are not
  # observation tickets; issuing one does not create a session or confirm time.
  def issue(context: {}, duration: nil)
    context = object!(context, CONTEXT_FIELDS)
    transaction do
      resolve_context(context)
      preference = preference!
      duration ||= preference.focus_duration_seconds
      duration!(duration)
      verifier.generate({ "user_id" => @user.id, "operation" => "focus.create", "uid" => SecureRandom.uuid,
        "context" => context, "duration" => duration }, purpose: "focus-create")
    end
  end

  def prepare(intent:, command_id:, version:, action: "prepare")
    validate_command!(command_id, version, "start", { "action" => action, "intent" => intent })
    raise Invalid, "Ação de preparação inválida" unless %w[prepare start_new].include?(action)
    claim = claim!(intent)
    transaction do
      session = @user.focus_sessions.find_by(uid: claim.fetch("uid"))
      previous = @user.focus_commands.find_by(command_id: command_id)
      if session
        raise Conflict, "Intenção já utilizada; confira o temporizador" unless previous&.focus_session_id == session.id
      else
        raise Conflict, "Chave já utilizada por outra intenção" if previous
        raise Conflict, "Preparação exige versão zero" unless version == 0
        ensure_slot!
        session = build_session(claim)
      end
      record(session, command_id, version, "start", { "action" => action, "intent" => intent }) do |target, sample|
        start(target, sample) if action == "start_new"
        outcome(target, clock: action == "start_new" ? sample : nil)
      end
    end
  end

  def command(uid:, command_id:, version:, kind:, parameters:)
    parameters = validate_command!(command_id, version, kind, parameters)
    raise Invalid, "Use preparação com intenção" if %w[prepare start_new].include?(parameters.fetch("action"))
    transaction do
      session = @user.focus_sessions.find_by!(uid: uid)
      record(session, command_id, version, kind, parameters) do |target, sample|
        raise Conflict, "Tentativa encerrada; confira o estado atual" unless FocusSession::OCCUPYING.include?(target.status)
        case parameters.fetch("action")
        when "start", "resume"
          expected = parameters.fetch("action") == "start" ? "ready" : "paused"
          require_status!(target, expected)
          raise Conflict, "Resolva o intervalo pendente antes de retomar" if recovery(target)
          start(target, sample)
          outcome(target, clock: sample)
        when "pause", "reconcile"
          pause(target, sample)
        when "resolve"
          resolve(target, parameters, sample)
        when "confirm"
          complete(target, sample)
        when "cancel"
          cancel(target, sample, "cancelled")
          outcome(target)
        when "restart"
          restart(target, parameters, sample)
        end
      end
    end
  end

  def preset(duration:, version:)
    duration!(duration)
    version!(version)
    transaction do
      preference = preference!
      raise Conflict, "Preferências alteradas em outra aba" unless preference.lock_version == version
      raise Conflict, "Encerre o foco ou substitua ready por reset explícito" if @user.focus_sessions.occupying.exists?
      preference.update!(focus_duration_seconds: duration)
      { "duration_seconds" => preference.focus_duration_seconds, "version" => preference.lock_version }
    end
  end

  # A consistent read; no intentions, receipts, transitions or timestamps saved.
  def read
    FocusSession.uncached { FocusSession.transaction { current } }
  end

  private

  def record(session, command_id, version, kind, parameters)
    previous = @user.focus_commands.find_by(command_id: command_id)
    receipt = FocusCommand.record!(user: @user, command_id: command_id, kind: kind, focus_session: session,
      expected_version: version, parameters: parameters) do |target|
      yield(target, @time.sample)
    end
    { "command_id" => receipt.command_id, "replayed" => previous.present?, "result" => receipt.result.deep_dup,
      "current" => current }
  end

  def current
    session = @user.focus_sessions.occupying.first
    sample = @time.sample
    preference = @user.user_preferences_scope.first
    { "server_now" => sample.fetch("wall"), "session" => session && snapshot(session),
      "timing" => session && @time.project(session, anchor: metadata(session)&.dig("clock"), sample: sample),
      "recovery" => session && recovery(session), "preset_seconds" => preference&.focus_duration_seconds,
      "preference_version" => preference&.lock_version }
  end

  def snapshot(session)
    session.attributes.slice("uid", "status", "duration_seconds", "elapsed_seconds", "started_at", "running_since",
      "deadline_at", "paused_at", "completed_at", "ended_at", "end_reason").as_json.merge(
        "version" => session.lock_version, "project_uid" => session.project&.uid, "task_uid" => session.task&.uid)
  end

  def outcome(session, clock: nil, recovery: nil, **extra)
    { "focus_contract" => 1, "session" => snapshot(session), "clock" => clock, "recovery" => recovery }.merge(extra.stringify_keys)
  end

  def metadata(session)
    receipt = session.focus_commands.order(id: :desc).first
    return nil unless receipt&.result&.fetch("focus_contract", nil) == 1
    unless receipt.result.dig("session", "version") == session.lock_version && receipt.result.dig("session", "uid") == session.uid
      raise Conflict, "Recibo incompatível com a versão da sessão; dados preservados"
    end
    receipt.result.merge("receipt_id" => receipt.id)
  end

  def recovery(session)
    data = metadata(session)
    data&.fetch("recovery", nil)&.merge("receipt_id" => data.fetch("receipt_id"), "version" => session.lock_version)
  end

  def start(session, sample)
    editable_context!(session)
    now = Time.iso8601(sample.fetch("wall"))
    save(session, sample, status: "running", started_at: session.started_at || now,
      paused_at: nil, running_since: now, deadline_at: now + session.duration_seconds - session.elapsed_seconds)
  end

  def pause(session, sample)
    require_status!(session, "running")
    timing = @time.project(session, anchor: metadata(session)&.dig("clock"), sample: sample)
    uncertain = timing.fetch("continuity") == "unknown"
    elapsed = uncertain ? session.elapsed_seconds : timing.fetch("nominal_seconds")
    pending = uncertain ? { "candidate_seconds" => timing.fetch("estimate_valid") ? timing.fetch("nominal_seconds") : nil,
      "reasons" => timing.fetch("reasons"), "checkpoint_seconds" => session.elapsed_seconds } : nil
    save(session, sample, status: elapsed == session.duration_seconds && !uncertain ? "awaiting_confirmation" : "paused",
      elapsed_seconds: elapsed, running_since: nil, deadline_at: nil,
      paused_at: elapsed == session.duration_seconds && !uncertain ? nil : Time.iso8601(sample.fetch("wall")))
    outcome(session, recovery: pending)
  end

  def resolve(session, parameters, sample)
    require_status!(session, "paused")
    pending = recovery(session)
    unless pending && parameters.fetch("recovery_id") == pending.fetch("receipt_id")
      raise Conflict, "Recuperação já resolvida ou substituída"
    end
    elapsed = session.elapsed_seconds
    if parameters.fetch("decision") == "accept_estimate"
      elapsed = pending.fetch("candidate_seconds")
      raise Invalid, "Estimativa inválida; mantenha checkpoint ou cancele" unless elapsed.is_a?(Integer) && elapsed.between?(session.elapsed_seconds, session.duration_seconds)
    end
    save(session, sample, elapsed_seconds: elapsed, status: elapsed == session.duration_seconds ? "awaiting_confirmation" : "paused",
      paused_at: elapsed == session.duration_seconds ? nil : session.paused_at)
    outcome(session, resolved_recovery_id: pending.fetch("receipt_id"), decision: parameters.fetch("decision"))
  end

  def complete(session, sample)
    if session.status == "running"
      timing = @time.project(session, anchor: metadata(session)&.dig("clock"), sample: sample)
      unless timing.fetch("continuity") == "observed" && timing.fetch("nominal_seconds") == session.duration_seconds
        raise Conflict, "Prazo não confirmado; pause/reconcilie antes de concluir"
      end
    else
      require_status!(session, "awaiting_confirmation")
    end
    now = Time.iso8601(sample.fetch("wall"))
    save(session, sample, status: "completed", elapsed_seconds: session.duration_seconds,
      running_since: nil, deadline_at: nil, paused_at: nil, completed_at: now, ended_at: now)
    outcome(session)
  end

  def cancel(session, sample, reason)
    elapsed = session.elapsed_seconds
    if session.status == "running"
      timing = @time.project(session, anchor: metadata(session)&.dig("clock"), sample: sample)
      elapsed = timing.fetch("nominal_seconds") if timing.fetch("continuity") == "observed"
    end
    save(session, sample, status: "cancelled", elapsed_seconds: elapsed, end_reason: reason,
      running_since: nil, deadline_at: nil, paused_at: nil, ended_at: Time.iso8601(sample.fetch("wall")))
  end

  def restart(session, parameters, sample)
    editable_context!(session, require_pending: false)
    claim = claim!(parameters.fetch("intent"))
    raise Conflict, "Intenção de reinício já utilizada" if @user.focus_sessions.exists?(uid: claim.fetch("uid"))
    resolve_context(claim.fetch("context"))
    if parameters.key?("preference_version")
      version!(parameters.fetch("preference_version"))
      preference = preference!
      raise Conflict, "Preferências alteradas em outra aba" unless preference.lock_version == parameters.fetch("preference_version")
      preference.update!(focus_duration_seconds: claim.fetch("duration"))
    end
    cancel(session, sample, "reset")
    fresh = build_session(claim)
    outcome(session, new_session_uid: fresh.uid, new_session: snapshot(fresh), preference_version: preference&.lock_version)
  end

  def save(session, sample, **attributes)
    session.assign_attributes(attributes)
    session.changed? ? session.save! : session.touch(time: Time.iso8601(sample.fetch("wall")))
  end

  def build_session(claim)
    project, task = resolve_context(claim.fetch("context"))
    @user.focus_sessions.create!(uid: claim.fetch("uid"), project: project, task: task, duration_seconds: claim.fetch("duration"))
  end

  def resolve_context(context)
    %w[project_uid task_uid].each do |field|
      raise Invalid, "UID deve ser texto" if !context[field].nil? && (!context[field].is_a?(String) || context[field].empty?)
    end
    project = @user.projects.find_by!(uid: context.fetch("project_uid")) if context["project_uid"]
    task = @user.tasks.find_by!(uid: context.fetch("task_uid")) if context["task_uid"]
    if task
      version!(context["task_version"])
      raise Conflict, "Tarefa mudou; confira o contexto" unless task.lock_version == context["task_version"] && task.project_id == project&.id
      raise Conflict, "Reabra a tarefa antes de iniciar foco" unless task.status == "pending"
    end
    if project
      version!(context["project_version"])
      raise Conflict, "Projeto mudou; confira o contexto" unless project.lock_version == context["project_version"]
      raise Conflict, "Projeto arquivado não permite novo trabalho" if project.status == "archived"
    end
    [ project, task ]
  end

  def editable_context!(session, require_pending: true)
    project = @user.projects.find(session.project_id) if session.project_id
    task = @user.tasks.find(session.task_id) if session.task_id
    current_project = @user.projects.find(task.project_id) if task&.project_id
    raise Conflict, "Projeto arquivado não permite iniciar ou retomar" if [ project, current_project ].compact.any? { |p| p.status == "archived" }
    raise Conflict, "Reabra a tarefa antes de retomar" if require_pending && task && task.status != "pending"
  end

  def ensure_slot!
    raise Conflict, "Já existe um Pomodoro global; confira a sessão atual" if @user.focus_sessions.occupying.exists?
  end

  def preference!
    preference = @user.user_preferences_scope.first
    raise Conflict, "Inicialize as preferências antes de preparar foco" unless preference&.initialized_at
    preference
  end

  def claim!(intent)
    value = verifier.verified(intent, purpose: "focus-create") if intent.is_a?(String)
    unless value.is_a?(Hash) && value["user_id"] == @user.id && value["operation"] == "focus.create" && value["uid"].is_a?(String)
      raise Invalid, "Intenção de foco inválida"
    end
    duration!(value["duration"])
    value
  end

  def validate_command!(command_id, version, kind, parameters)
    raise Invalid, "command_id inválido" unless command_id.is_a?(String) && command_id.match?(/\A[A-Za-z0-9_-]{1,128}\z/)
    version!(version)
    raise Invalid, "Kind inválido" unless ACTIONS.key?(kind)
    parameters = object!(parameters, %w[action intent preference_version recovery_id decision])
    action = parameters["action"]
    raise Invalid, "Ação incompatível com kind" unless ACTIONS.fetch(kind).include?(action)
    allowed = case action
    when "prepare", "start_new", "restart" then %w[action intent preference_version]
    when "resolve" then %w[action recovery_id decision]
    else %w[action]
    end
    raise Invalid, "Parâmetros incompatíveis" unless (parameters.keys - allowed).empty?
    if action == "resolve"
      version!(parameters["recovery_id"])
      raise Invalid, "Decisão inválida" unless %w[keep_checkpoint accept_estimate].include?(parameters["decision"])
    end
    parameters
  end

  def object!(value, keys)
    raise Invalid, "Objeto inválido" unless value.is_a?(Hash)
    value = value.stringify_keys
    raise Invalid, "Campo não permitido" unless (value.keys - keys).empty?
    value
  end

  def duration!(value)
    raise Invalid, "Use exclusivamente 25 ou 45 minutos" unless [ 1500, 2700 ].include?(value) && value.is_a?(Integer)
  end

  def version!(value)
    raise Conflict, "Versão inteira obrigatória" unless value.is_a?(Integer) && value >= 0
  end

  def require_status!(session, status)
    raise Conflict, "Ação incompatível com estado #{session.status}" unless session.status == status
  end

  def verifier
    Rails.application.message_verifier("focus-intention")
  end

  def transaction(&block)
    FocusSession.uncached do
      FocusSession.transaction do
        FocusSession.connection.materialize_transactions
        block.call
      end
    end
  end
end
