module ProjectWriteProtection
  extend ActiveSupport::Concern

  included do
    validate :project_is_owned_and_editable
    before_destroy :protect_archived_project
  end

  private

  def project_is_owned_and_editable
    if project_id && !Project.exists?(id: project_id, user_id: user_id)
      errors.add(:project, "não pertence ao proprietário")
    end
    errors.add(:base, "Restaure o projeto para alterar seus registros") if protected_project?
  end

  def protected_project?
    ids = [ project_id, persisted? ? project_id_in_database : nil ].compact.uniq
    Project.where(id: ids, status: "archived").exists?
  end

  def protect_archived_project
    return unless protected_project?
    errors.add(:base, "Restaure o projeto para alterar seus registros")
    throw :abort
  end
end
