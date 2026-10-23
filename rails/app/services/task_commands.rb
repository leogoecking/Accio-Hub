class TaskCommands
  class Conflict < StandardError; end
  class ArchivedProject < Conflict; end
  class InvalidIntent < StandardError; end
  FIELDS = %w[title priority].freeze

  def initialize(user)
    @user = user
  end

  def issue(context: nil)
    verifier.generate({ "user_id" => @user.id, "operation" => "task.create", "uid" => SecureRandom.uuid, "context" => context }, purpose: "task-create")
  end

  def create(intent, attributes, context: nil, destination: nil)
    claim = verifier.verified(intent, purpose: "task-create") if intent.is_a?(String)
    unless claim.is_a?(Hash) && claim["user_id"] == @user.id && claim["operation"] == "task.create" && claim["uid"].present? && claim["context"] == context
      raise InvalidIntent, "Intenção inválida. Abra um novo formulário; seus campos foram mantidos."
    end
    transaction do
      project = editable_project(context || destination)
      values = { "priority" => "normal" }.merge(clean(attributes)).merge(project: project)
      existing = @user.tasks.find_by(uid: claim.fetch("uid"))
      if existing
        editable_project(existing.project&.uid)
        unless FIELDS.all? { |field| existing[field] == values[field] } && existing.project_id == project&.id
          raise Conflict, "Esta intenção já criou uma tarefa com dados diferentes. Sua edição foi mantida."
        end
        existing
      else
        task = @user.tasks.create!(values.merge(uid: claim.fetch("uid"), position: (@user.tasks.maximum(:position) || -1) + 1))
        activity([ project ])
        task
      end
    end
  end

  def change(uid, version:, operation:, attributes: {}, context: nil, destination: nil)
    transaction do
      scope = @user.tasks
      scope = scope.where(project: @user.projects.find_by!(uid: context)) if context
      task = scope.find_by!(uid: uid)
      origin = editable_project(task.project&.uid)
      raise Conflict, "Outra aba alterou esta tarefa. Sua edição foi mantida; confira a versão atual." unless version.is_a?(Integer) && task.lock_version == version
      case operation
      when "edit"
        target = context ? origin : editable_project(destination)
        task.assign_attributes(clean(attributes).merge(project: target))
      when "status"
        value = attributes.fetch("status")
        raise ArgumentError, "Estado de tarefa inválido" unless %w[pending completed].include?(value)
        task.assign_attributes(status: value, completed_at: value == "completed" ? Time.current : nil) if task.status != value
        target = origin
      else raise ArgumentError, "Operação de tarefa inválida"
      end
      if task.changed?
        task.save!
        activity([ origin, target ])
      end
      task
    end
  end

  private

  def editable_project(uid)
    return nil if uid.nil?
    project = @user.projects.find_by!(uid: uid)
    raise ArchivedProject, "Projeto arquivado é somente leitura. Restaure-o antes de alterar tarefas." if project.status == "archived"
    project
  end

  def activity(projects)
    projects.compact.uniq(&:id).each { |project| project.update!(last_activity_at: Time.current) }
  end

  def clean(attributes)
    attributes.stringify_keys.slice(*FIELDS).tap do |values|
      raise ArgumentError, "Campos da tarefa devem ser texto" unless values.values.all? { |value| value.is_a?(String) }
      values["title"] = values["title"].strip if values.key?("title")
    end
  end

  def verifier
    Rails.application.message_verifier("task-intention")
  end

  def transaction(&block)
    Task.uncached do
      Task.transaction do
        Task.connection.materialize_transactions
        block.call
      end
    end
  end
end
