class Project < ApplicationRecord
  include PublicUid

  STATUSES = %w[active paused archived].freeze
  ICONS = %w[grid code book target rss calendar cloud music check mail].freeze
  TINTS = %w[mint purple pink blue orange gold].freeze

  belongs_to :user
  has_many :tasks, dependent: :restrict_with_error
  has_many :project_references, dependent: :restrict_with_error
  has_many :widget_placements, dependent: :restrict_with_error
  has_many :focus_sessions, dependent: :restrict_with_error

  before_validation :normalize_name
  validates :name, presence: true, length: { maximum: 80 }
  validates :name_key, presence: true, uniqueness: { scope: :user_id }
  validates :description, length: { maximum: 500 }
  validates :status, inclusion: { in: STATUSES }
  validates :icon, inclusion: { in: ICONS }
  validates :tint, inclusion: { in: TINTS }
  validates :color, format: { with: /\A#[0-9a-f]{6}\z/i }, allow_nil: true
  validates :favorite, inclusion: { in: [ true, false ] }
  validates :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :archive_state
  before_destroy do
    errors.add(:base, "Use arquivamento; projetos não são excluídos")
    throw :abort
  end

  def archive!
    return self if status == "archived"
    update!(archived_from: status, archived_at: Time.current, status: "archived", last_activity_at: Time.current)
    self
  end

  def restore!
    return self unless status == "archived"
    update!(status: archived_from || "active", archived_from: nil, archived_at: nil, last_activity_at: Time.current)
    self
  end

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/[[:space:]]+/, " ")
    self.name_key = name.unicode_normalize(:nfkc).downcase
  end

  def archive_state
    errors.add(:archived_from, "inválido") unless archived_from.nil? || %w[active paused].include?(archived_from)
    if status != "archived" && (archived_from || archived_at)
      errors.add(:base, "Projeto não arquivado não possui estado de arquivamento")
    end
    return unless persisted? && status_in_database == "archived" && has_changes_to_save?
    allowed = %w[status archived_from archived_at last_activity_at updated_at lock_version]
    restoring = status == (archived_from_in_database || "active") && archived_from.nil? && archived_at.nil?
    errors.add(:base, "Projeto arquivado é somente leitura; use restauração") unless restoring && (changed_attribute_names_to_save - allowed).empty?
  end
end
