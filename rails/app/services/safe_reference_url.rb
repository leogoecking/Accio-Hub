require "uri"
require "ipaddr"

# Shared command/presentation policy; parses locally without DNS or HTTP requests.
class SafeReferenceUrl
  def self.call(value)
    return unless value.is_a?(String) && value.present? && !value.match?(/[\s\\\x00-\x1f\x7f]/) && !value.match?(/%(?![0-9a-f]{2})/i)
    authority = value[%r{\Ahttps?://([^/?#]*)}i, 1]
    return unless authority&.match?(/\A(?:\[[0-9a-f:.]+\]|[a-z0-9.-]+)(?::[0-9]+)?\z/i)
    parsed = URI.parse(value)
    return unless parsed.is_a?(URI::HTTP) && parsed.userinfo.nil? && parsed.host.present? && (1..65_535).cover?(parsed.port)
    host = parsed.hostname
    if parsed.host.start_with?("[")
      return unless IPAddr.new(host).ipv6?
    else
      labels = host.delete_suffix(".").split(".", -1)
      return unless host.bytesize <= 253 && labels.any? && labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i) }
      # WHATWG treats a numeric final label as IPv4, even on an apparent DNS name.
      # Only four canonical decimal octets are allowed; keep the original string.
      if labels.last.match?(/\A(?:[0-9]+|0x[0-9a-f]*)\z/i)
        octets = host.split(".", -1)
        return unless octets.size == 4 && octets.all? { |octet| octet.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && octet.to_i <= 255 }
      end
    end
    value
  rescue URI::InvalidURIError, IPAddr::InvalidAddressError, ArgumentError
    nil
  end
end
