class Current < ActiveSupport::CurrentAttributes
  attribute :auth_session
  delegate :user, to: :auth_session, allow_nil: true
end
