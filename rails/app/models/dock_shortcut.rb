class DockShortcut < ApplicationRecord
  include OrderedPlacement

  MODULE_KEYS = %w[tasks calendar focus knowledge projects feed backup email].freeze
  belongs_to :user
  attr_readonly :user_id, :module_key
  validates :module_key, inclusion: { in: MODULE_KEYS }, uniqueness: { scope: :user_id }
  validates :position, :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: :user_id }
  validates :visible, inclusion: { in: [ true, false ] }

  def self.reorder!(user:, module_keys:, expected_version:)
    reorder_scope!(user: user, scope: user.dock_shortcuts, key: :module_key, keys: module_keys, expected_version: expected_version)
  end
end
