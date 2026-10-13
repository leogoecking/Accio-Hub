class ReferenceCommands
  class Conflict < StandardError; end
  class ArchivedProject < Conflict; end
  class InvalidIntent < StandardError; end
  FIELDS = %w[title kind url description].freeze

  def initialize(user)
    @user = user
  end

  def issue(context:)
    verifier.generate({ "user_id" => @user.id, "operation" => "reference.create", "uid" => SecureRandom.uuid, "context" => context }, purpose: "reference-create")
  end

  def create(intent, attributes, context:)
    claim = verifier.verified(intent, purpose: "reference-create") if intent.is_a?(String)
    unless claim.is_a?(Hash) && claim["user_id"] == @user.id && claim["operation"] == "reference.create" && claim["uid"].present? && claim["context"] == context
      raise InvalidIntent, "Intenção inválida. Abra um novo formulário; seus campos foram mantidos."
    end
    transaction do
      project = editable_project(context)
      values = { "kind" => "link", "url" => "", "description" => "" }.merge(clean(attributes))
      existing = @user.project_references.find_by(uid: claim.fetch("uid"))
      if existing
        unless existing.project_id == project.id && FIELDS.all? { |field| existing[field] == values[field] }
          raise Conflict, "Esta intenção já criou uma referência com dados diferentes. Sua edição foi mantida."
        end
        existing
      else
        reference = project.project_references.build(values.merge(user: @user, uid: claim.fetch("uid"), position: (project.project_references.maximum(:position) || -1) + 1))
        save(reference, project)
      end
    end
  end

  def change(uid, version:, attributes:, context:)
    transaction do
      project = @user.projects.find_by!(uid: context)
      reference = project.project_references.where(user: @user).find_by!(uid: uid)
      editable_project(context)
      raise Conflict, "Outra aba alterou esta referência. Sua edição foi mantida; confira a versão atual." unless version.is_a?(Integer) && reference.lock_version == version
      reference.assign_attributes(clean(attributes))
      reference.changed? ? save(reference, project) : reference
    end
  end

  private

  def save(reference, project)
    if reference.url.present? && !SafeReferenceUrl.call(reference.url)
      reference.errors.add(:url, "use HTTP/HTTPS com host válido, sem credenciais ou caracteres inválidos")
      raise ActiveRecord::RecordInvalid, reference
    end
    reference.save!
    project.update!(last_activity_at: Time.current)
    reference
  end

  def editable_project(uid)
    project = @user.projects.find_by!(uid: uid)
    raise ArchivedProject, "Projeto arquivado é somente leitura. Restaure-o antes de alterar referências." if project.status == "archived"
    project
  end

  def clean(attributes)
    attributes.stringify_keys.slice(*FIELDS).tap do |values|
      raise ArgumentError, "Campos da referência devem ser texto" unless values.values.all? { |value| value.is_a?(String) }
      raise ArgumentError, "URL contém caracteres de controle" if values["url"]&.match?(/[\x00-\x1f\x7f]/)
      values.transform_values! { |value| value.strip }
    end
  end

  def verifier
    Rails.application.message_verifier("reference-intention")
  end

  def transaction(&block)
    ProjectReference.uncached do
      ProjectReference.transaction do
        ProjectReference.connection.materialize_transactions
        block.call
      end
    end
  end
end
