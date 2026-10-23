# Backend contract only. P1.2E1 deliberately does not connect the visual timer.
class FocusController < StudioController
  # This API accepts an explicit envelope; Rails' inferred JSON root would add
  # a second, implicit payload and defeat the strict top-level field contract.
  wrap_parameters false
  rescue_from FocusCommands::Invalid, ArgumentError, KeyError, ActionController::ParameterMissing, with: :invalid_focus
  rescue_from FocusCommands::Conflict, FocusCommand::IncompatibleRetry, ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique, with: :focus_conflict
  rescue_from ActiveRecord::RecordNotFound, with: :missing_focus
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_focus

  def state
    render json: engine.read
  end

  def intention
    body!(%w[context duration_seconds])
    context = object(params[:context] || {})
    %w[project_uid task_uid].each { |field| context[field] = decode(context[field]) if context[field] }
    %w[project_version task_version].each { |field| context[field] = integer(context[field]) if context.key?(field) }
    render json: { intent: engine.issue(context: context, duration: params[:duration_seconds]) }
  end

  def prepare
    body!(%w[intent command_id version operation])
    render json: engine.prepare(intent: params[:intent], command_id: params[:command_id], version: integer(params[:version]), action: params[:operation] || "prepare")
  end

  def command
    body!(%w[command_id version kind parameters])
    render json: engine.command(uid: decode(params[:uid]), command_id: params[:command_id], version: integer(params[:version]),
      kind: params[:kind], parameters: object(params.require(:parameters)))
  end

  def preset
    body!(%w[duration_seconds version])
    render json: engine.preset(duration: params[:duration_seconds], version: integer(params[:version]))
  end

  private

  def engine
    @engine ||= FocusCommands.new(Current.user)
  end

  def body!(keys)
    raise FocusCommands::Invalid, "Campo não permitido" unless (request.request_parameters.keys - keys).empty? && request.query_parameters.empty?
  end

  def object(value)
    return value.to_unsafe_h if value.is_a?(ActionController::Parameters)
    raise FocusCommands::Invalid, "Objeto inválido" unless value.is_a?(Hash)
    value
  end

  def integer(value)
    return value if value.is_a?(Integer) && value >= 0
    return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
    raise FocusCommands::Conflict, "Versão inteira obrigatória"
  end

  def decode(value)
    PublicUid.decode(value)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def invalid_focus(error)
    message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(". ") : error.message
    render json: { error: "invalid_focus", message: message }, status: :unprocessable_entity
  end

  def focus_conflict(error)
    render json: { error: "focus_conflict", message: error.message }, status: :conflict
  end

  def missing_focus
    render json: { error: "not_found", message: "Sessão ou contexto não encontrado" }, status: :not_found
  end
end
