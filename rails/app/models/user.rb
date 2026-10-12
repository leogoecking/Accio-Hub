class User < ApplicationRecord
  has_secure_password
  has_many :auth_sessions, dependent: :destroy
  normalizes :email_address, with: ->(value) { value.strip.downcase }
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }
  validate :single_administrator, on: :create
  before_create { self.id = 1 }

  private

  def single_administrator
    errors.add(:base, "Já existe um administrador") if User.exists?
  end
end
