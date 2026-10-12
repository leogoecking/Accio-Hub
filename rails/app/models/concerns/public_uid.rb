require "base64"

module PublicUid
  extend ActiveSupport::Concern

  included do
    attr_readonly :uid, :user_id
    before_validation { self.uid ||= SecureRandom.uuid }
    validates :uid, presence: true, uniqueness: { scope: :user_id }
    validate do
      errors.add(:uid, "deve ser texto UTF-8 válido sem NUL") unless uid.is_a?(String) && uid.valid_encoding? && !uid.include?("\0")
    end
  end

  def self.encode(uid)
    value = uid.to_s.encode(Encoding::UTF_8)
    raise ArgumentError, "UID inválido" if value.blank? || !value.valid_encoding? || value.include?("\0")
    "u-#{Base64.urlsafe_encode64(value, padding: false)}"
  end

  def self.decode(token)
    raise ArgumentError, "UID de rota inválido" unless token.is_a?(String) && token.match?(/\Au-[A-Za-z0-9_-]+\z/)
    value = Base64.urlsafe_decode64(token.delete_prefix("u-")).force_encoding(Encoding::UTF_8)
    raise ArgumentError, "UID de rota inválido" unless value.valid_encoding? && encode(value) == token
    value
  end

  def to_param
    PublicUid.encode(uid)
  end
end
