require "uri"

class ProjectReference < ApplicationRecord
  include PublicUid
  include ProjectWriteProtection

  belongs_to :user
  belongs_to :project
  validates :title, presence: true, length: { maximum: 120 }
  validates :kind, inclusion: { in: %w[link material] }
  validates :description, length: { maximum: 2000 }
  validates :url, presence: true, if: -> { kind == "link" }
  validates :position, :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :safe_url

  private

  def safe_url
    return if url.blank?
    parsed = URI.parse(url)
    errors.add(:url, "use HTTP/HTTPS sem credenciais") unless parsed.is_a?(URI::HTTP) && parsed.host.present? && parsed.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:url, "inválida")
  end
end
