class ProjectCommands
  class Conflict < StandardError; end
  class InvalidIntent < StandardError; end
  FIELDS = %w[name description icon color].freeze

  def initialize(user)
    @user = user
  end

  def issue
    verifier.generate({ "user_id" => @user.id, "operation" => "project.create", "uid" => SecureRandom.uuid }, purpose: "project-create")
  end

  def create(intent, attributes)
    claim = verifier.verified(intent, purpose: "project-create")
    unless claim.is_a?(Hash) && claim["user_id"] == @user.id && claim["operation"] == "project.create" && claim["uid"].present?
      raise InvalidIntent, "Intenção inválida. Abra um novo formulário; seus campos foram mantidos."
    end
    transaction do
      candidate = @user.projects.build(clean(attributes).merge(uid: claim.fetch("uid")))
      existing = @user.projects.find_by(uid: candidate.uid)
      # Normalize with the same model contract; uniqueness is checked only for new records.
      candidate.valid?
      if existing
        equivalent = FIELDS.all? { |field| comparable(existing[field]) == comparable(candidate[field]) }
        raise Conflict, "Esta intenção já criou um projeto com dados diferentes. Sua edição foi mantida." unless equivalent
        existing
      else
        candidate.last_activity_at = Time.current
        candidate.save!
        candidate
      end
    end
  end

  def change(uid, version:, operation:, attributes: {})
    transaction do
      project = @user.projects.find_by!(uid: uid)
      raise Conflict, "Outra aba alterou este projeto. Sua edição foi mantida; confira a versão atual." unless version.is_a?(Integer) && project.lock_version == version
      raise Conflict, "Projeto arquivado é somente leitura. Restaure-o antes de alterar." if project.status == "archived" && operation != "restore"
      case operation
      when "edit"
        project.assign_attributes(clean(attributes))
        project.valid?
        project.last_activity_at = Time.current if project.changed?
        project.save!
      when "favorite"
        value = attributes.fetch("favorite")
        raise ArgumentError, "Favorito inválido" unless [ true, false ].include?(value)
        project.update!(favorite: value)
      when "status"
        value = attributes.fetch("status")
        raise ArgumentError, "Estado inválido" unless %w[active paused].include?(value)
        project.update!(status: value, last_activity_at: Time.current) if project.status != value
      when "archive" then project.archive!
      when "restore" then project.restore!
      else raise ArgumentError, "Operação inválida"
      end
      project
    end
  end

  private

  def clean(attributes)
    attributes.stringify_keys.slice(*FIELDS).tap do |value|
      raise ArgumentError, "Campos do projeto devem ser texto" unless value.values.all? { |field| field.nil? || field.is_a?(String) }
      value["description"] = value["description"].to_s.strip if value.key?("description")
      value["color"] = value["color"].presence&.downcase if value.key?("color")
    end
  end

  def comparable(value)
    value.nil? ? "" : value
  end

  def verifier
    Rails.application.message_verifier("project-intention")
  end

  def transaction(&block)
    Project.uncached do
      Project.transaction do
        Project.connection.materialize_transactions
        block.call
      end
    end
  end
end
