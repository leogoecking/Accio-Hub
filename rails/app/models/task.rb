class Task < ApplicationRecord
  include PublicUid
  include ProjectWriteProtection

  belongs_to :user
  belongs_to :project, optional: true
  has_many :focus_sessions, dependent: :restrict_with_error
  validates :title, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: %w[pending completed] }
  validates :priority, inclusion: { in: %w[normal high] }
  validates :position, :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate { errors.add(:completed_at, "somente em tarefa concluída") if status != "completed" && completed_at }
end
