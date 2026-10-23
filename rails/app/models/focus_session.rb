class FocusSession < ApplicationRecord
  include PublicUid

  STATUSES = %w[ready running paused awaiting_confirmation completed cancelled].freeze
  OCCUPYING = %w[ready running paused awaiting_confirmation].freeze
  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :task, optional: true
  has_many :focus_commands, dependent: :restrict_with_error
  attr_readonly :project_id, :task_id
  scope :occupying, -> { where(status: OCCUPYING) }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_seconds, inclusion: { in: [ 1500, 2700 ] }
  validates :elapsed_seconds, :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :end_reason, inclusion: { in: %w[reset cancelled interrupted] }, allow_nil: true
  validate :owned_context
  validate :timing_state
  validate :archived_context_write
  validate do
    if persisted? && %w[completed cancelled].include?(status_in_database) && has_changes_to_save?
      errors.add(:base, "Tentativa encerrada é imutável")
    end
  end
  before_destroy do
    errors.add(:base, "Tentativas de foco são preservadas")
    throw :abort
  end
  validate do
    if OCCUPYING.include?(status) && self.class.occupying.where(user_id: user_id).where.not(id: id).exists?
      errors.add(:base, "Já existe uma sessão ocupando o temporizador")
    end
  end

  private

  def archived_context_write
    return unless persisted? && has_changes_to_save? && project_id && Project.exists?(id: project_id, status: "archived")
    allowed = %w[status elapsed_seconds running_since deadline_at paused_at completed_at ended_at end_reason lock_version updated_at]
    closing = %w[paused awaiting_confirmation completed cancelled].include?(status) || (status == "running" && status_in_database == "running")
    errors.add(:base, "Projeto arquivado permite apenas encerrar ou reconciliar foco existente") unless closing && (changed_attribute_names_to_save - allowed).empty?
  end

  def owned_context
    errors.add(:project, "não pertence ao proprietário") if project_id && !Project.exists?(id: project_id, user_id: user_id)
    errors.add(:task, "não pertence ao proprietário") if task_id && !Task.exists?(id: task_id, user_id: user_id)
    return unless new_record?
    errors.add(:project, "arquivado") if project_id && Project.exists?(id: project_id, status: "archived")
    errors.add(:project, "deve ser o contexto da tarefa") if task && task.project_id != project_id
  end

  def timing_state
    errors.add(:elapsed_seconds, "excede a duração") if elapsed_seconds && duration_seconds && elapsed_seconds > duration_seconds
    running = status == "running"
    errors.add(:base, "Segmento em execução incompatível") unless running == (running_since.present? && deadline_at.present?) && (running || (running_since.nil? && deadline_at.nil?))
    errors.add(:deadline_at, "deve seguir o início do segmento") if running && running_since && deadline_at && deadline_at <= running_since
    errors.add(:started_at, "obrigatório") if %w[running paused awaiting_confirmation completed].include?(status) && started_at.nil?
    errors.add(:paused_at, "incompatível") unless (status == "paused") == paused_at.present?
    errors.add(:completed_at, "incompatível") unless (status == "completed") == completed_at.present?
    errors.add(:ended_at, "incompatível") unless %w[completed cancelled].include?(status) == ended_at.present?
    errors.add(:elapsed_seconds, "deve completar a duração") if %w[awaiting_confirmation completed].include?(status) && elapsed_seconds != duration_seconds
    errors.add(:base, "Sessão preparada não tem tempo iniciado") if status == "ready" && (elapsed_seconds != 0 || started_at)
    errors.add(:end_reason, "somente em cancelamento") if status != "cancelled" && end_reason
  end
end
