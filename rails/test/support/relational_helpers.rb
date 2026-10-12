module RelationalHelpers
  def relational_user
    @relational_user ||= synthetic_admin.first
  end

  def project_for(user = relational_user, **attributes)
    user.projects.create!({ name: "Projeto #{SecureRandom.hex(4)}" }.merge(attributes))
  end

  def second_synthetic_user
    connection = User.connection
    # Only for adversarial ownership fixtures: preserve the production id=1 rule.
    raise "Only synthetic test fixtures" unless Rails.env.test?
    connection.execute("PRAGMA ignore_check_constraints = ON")
    User.insert_all!([ { id: 2, email_address: "second@example.test", password_digest: "synthetic", created_at: Time.current, updated_at: Time.current } ])
    User.find(2)
  ensure
    connection&.execute("PRAGMA ignore_check_constraints = OFF")
  end

  def direct_insert(model, **attributes)
    record = model.new(attributes)
    record.uid ||= SecureRandom.uuid if record.has_attribute?(:uid)
    record.name_key ||= record.name.downcase if model == Project
    record.created_at = record.updated_at = Time.current
    model.insert_all!([ record.attributes.except("id") ])
  end

  def prepared_focus(user = relational_user, **attributes)
    user.focus_sessions.create!(attributes)
  end
end

ActiveSupport::TestCase.include RelationalHelpers
