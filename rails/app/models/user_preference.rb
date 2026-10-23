class UserPreference < ApplicationRecord
  belongs_to :user
  attr_readonly :user_id
  validates :user_id, uniqueness: true
  validates :theme, inclusion: { in: %w[dark light] }
  validates :wallpaper, inclusion: { in: %w[northern ember ocean graphite] }
  validates :accent, format: { with: /\A#[0-9a-f]{6}\z/i }
  validates :density, inclusion: { in: [ "comfortable" ] }
  validates :music_enabled, :music_expanded, :project_library_favorites_only, inclusion: { in: [ true, false ] }
  validates :focus_duration_seconds, inclusion: { in: [ 1500, 2700 ] }
  validates :project_library_status, inclusion: { in: %w[all active paused archived] }
  validates :project_library_sort, inclusion: { in: %w[name recent] }
  validates :preferences_schema_version, numericality: { only_integer: true, greater_than: 0 }
  validates :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :legacy_cookie_digest, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validate do
    if legacy_cookie_backup && !legacy_cookie_backup.is_a?(Hash)
      errors.add(:legacy_cookie_backup, "deve ser objeto JSON")
    end
  end
end
