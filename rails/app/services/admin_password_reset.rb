class AdminPasswordReset
  def self.call(password:, confirmation:)
    User.transaction do
      administrator = User.lock.find(1)
      if password.blank?
        administrator.errors.add(:password, :blank)
        raise ActiveRecord::RecordInvalid, administrator
      end

      administrator.update!(password: password, password_confirmation: confirmation)
      administrator.auth_sessions.delete_all
    end
  end
end
