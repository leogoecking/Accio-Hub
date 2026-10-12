module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  def authenticated?
    Current.auth_session ||= AuthSession.active.find_by(id: cookies.signed[:auth_session_id])
  end

  private

  def require_authentication
    return if authenticated?
    respond_to do |format|
      format.html { redirect_to new_session_path, status: :see_other }
      format.json { head :unauthorized }
    end
  end

  def start_session(user)
    reset_session
    Current.auth_session = user.auth_sessions.create!(expires_at: 12.hours.from_now)
    cookies.signed[:auth_session_id] = {
      value: Current.auth_session.id, expires: Current.auth_session.expires_at,
      httponly: true, same_site: :strict, secure: request.ssl?
    }
  end

  def end_session
    Current.auth_session&.destroy!
    Current.auth_session = nil
    cookies.delete(:auth_session_id)
    reset_session
  end
end
