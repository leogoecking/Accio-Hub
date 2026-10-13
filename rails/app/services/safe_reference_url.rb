require "uri"
require "ipaddr"

# Shared command/presentation policy; parses locally without DNS or HTTP requests.
class SafeReferenceUrl
  def self.call(value)
    return unless value.is_a?(String) && value.present? && !value.match?(/[\s\\\x00-\x1f\x7f]/) && !value.match?(/%(?![0-9a-f]{2})/i)
    parsed = URI.parse(value)
    return unless parsed.is_a?(URI::HTTP) && parsed.userinfo.nil? && !value.split("/", 4)[2].to_s.split(/[?#]/, 2).first.to_s.include?("@") && parsed.host.present? && (1..65_535).cover?(parsed.port)
    host = parsed.hostname
    if host.include?(":") || host.match?(/\A[0-9.]+\z/)
      address = IPAddr.new(host)
      return if address.ipv4? && host.split(".").size != 4
    else
      labels = host.delete_suffix(".").split(".", -1)
      return unless host.bytesize <= 253 && labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i) }
    end
    value
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError, ArgumentError
    nil
  end
end
