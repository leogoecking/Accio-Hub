require "ipaddr"

class LoopbackOnly
  def initialize(app)
    @app = app
  end

  def call(env)
    # Check the socket peer, not spoofable forwarding headers.
    peer = IPAddr.new(env.fetch("REMOTE_ADDR", ""))
    return @app.call(env) if peer.loopback?
    forbidden
  rescue IPAddr::InvalidAddressError
    forbidden
  end

  private

  def forbidden
    [ 403, { "content-type" => "text/plain; charset=utf-8" }, [ "Accio Hub P1.1 aceita somente conexões locais." ] ]
  end
end
