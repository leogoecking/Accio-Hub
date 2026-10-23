class WidgetPlacement < ApplicationRecord
  include OrderedPlacement
  include ProjectWriteProtection

  HOME_WIDGET_KEYS = %w[tasks focus calendar feed notes backup projects].freeze
  PROJECT_WIDGET_KEYS = %w[tasks focus notes info].freeze
  WIDGET_KEYS = (HOME_WIDGET_KEYS + PROJECT_WIDGET_KEYS).uniq.freeze
  SPANS = [ 3, 4, 5, 6, 8, 12 ].freeze
  belongs_to :user
  belongs_to :project, optional: true
  attr_readonly :user_id, :widget_key, :context, :project_id
  validates :context, inclusion: { in: %w[home project] }
  validates :widget_key, inclusion: { in: WIDGET_KEYS }, uniqueness: { scope: [ :user_id, :context, :project_id ] }
  validates :span, inclusion: { in: SPANS }
  validates :visible, inclusion: { in: [ true, false ] }
  validates :position, :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: [ :user_id, :context, :project_id ] }
  validate do
    errors.add(:project, "incompatível com contexto") unless (context == "home" && project_id.nil?) || (context == "project" && project_id.present?)
    catalog = context == "home" ? HOME_WIDGET_KEYS : PROJECT_WIDGET_KEYS
    errors.add(:widget_key, "incompatível com contexto") unless catalog.include?(widget_key)
  end

  def self.reorder!(user:, widget_keys:, expected_version:, context: "home", project: nil)
    unless (context == "home" && project.nil?) || (context == "project" && project&.persisted? && project.user_id == user.id)
      raise ArgumentError, "Contexto de widgets inválido"
    end
    if project && Project.exists?(id: project.id, status: "archived")
      raise ArgumentError, "Projeto arquivado é somente leitura"
    end
    scope = user.widget_placements.where(context: context, project_id: project&.id)
    reorder_scope!(user: user, scope: scope, key: :widget_key, keys: widget_keys, expected_version: expected_version)
  end
end
