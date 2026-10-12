class User < ApplicationRecord
  has_secure_password
  has_many :auth_sessions, dependent: :destroy
  has_many :projects, dependent: :restrict_with_error
  has_many :tasks, dependent: :restrict_with_error
  has_many :project_references, dependent: :restrict_with_error
  has_one :user_preference, dependent: :restrict_with_error
  has_many :dock_shortcuts, dependent: :restrict_with_error
  has_many :widget_placements, dependent: :restrict_with_error
  has_many :focus_sessions, dependent: :restrict_with_error
  has_many :focus_commands, dependent: :restrict_with_error
  normalizes :email_address, with: ->(value) { value.strip.downcase }
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }
  validate :single_administrator, on: :create
  before_create { self.id = 1 }

  # Avoid a has_one cached in memory after a rolled-back bootstrap.
  def user_preferences_scope
    UserPreference.where(user_id: id)
  end

  private

  def single_administrator
    errors.add(:base, "Já existe um administrador") if User.exists?
  end
end
