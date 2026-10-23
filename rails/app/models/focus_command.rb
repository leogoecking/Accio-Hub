require "digest"

class FocusCommand < ApplicationRecord
  KINDS = %w[start pause reset complete].freeze
  class IncompatibleRetry < StandardError; end

  belongs_to :user
  belongs_to :focus_session
  validates :command_id, presence: true, uniqueness: { scope: :user_id }
  validates :kind, inclusion: { in: KINDS }
  validates :expected_lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :request_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate do
    errors.add(:focus_session, "não pertence ao proprietário") if focus_session && focus_session.user_id != user_id
    errors.add(:base, "Payload e resultado devem ser objetos JSON") unless parameters.is_a?(Hash) && result.is_a?(Hash)
  end

  def readonly?
    persisted? || super
  end

  # Atomic receipt primitive only. Timer transitions and HTTP/UI are P1.2E.
  def self.record!(user:, command_id:, kind:, focus_session:, expected_version:, parameters: {})
    raise ArgumentError, "Comando inválido" unless KINDS.include?(kind) && command_id.is_a?(String) && command_id.present? && expected_version.is_a?(Integer) && expected_version >= 0 && parameters.is_a?(Hash)
    payload = canonical_json(parameters)
    digest = Digest::SHA256.hexdigest(JSON.generate([ kind, focus_session.id, expected_version, payload ]))

    transaction do
      previous = user.focus_commands.find_by(command_id: command_id)
      if previous
        raise IncompatibleRetry, "Chave de comando reutilizada com outra solicitação" unless previous.request_digest == digest
        next previous
      end

      session = user.focus_sessions.find(focus_session.id)
      raise ActiveRecord::StaleObjectError.new(session, "command") unless session.lock_version == expected_version
      outcome = yield(session)
      user.focus_commands.create!(command_id: command_id, kind: kind, focus_session: session,
        expected_lock_version: expected_version, request_digest: digest, parameters: parameters, result: outcome)
    end
  end

  def self.canonical_json(value)
    case value
    when Hash
      raise ArgumentError, "Chaves JSON inválidas" unless value.keys.all?(String)
      value.keys.sort.to_h { |key| [ key, canonical_json(value[key]) ] }
    when Array
      value.map { |item| canonical_json(item) }
    when String, Integer, TrueClass, FalseClass, NilClass
      value
    when Float
      raise ArgumentError, "Número JSON inválido" unless value.finite?
      value
    else
      raise ArgumentError, "Valor JSON inválido"
    end
  end
  private_class_method :canonical_json
end
