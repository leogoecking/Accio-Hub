# Run only against the dedicated synthetic database, after db:prepare.
expected = Rails.root.join("tmp/p11-browser.sqlite3").expand_path
actual = Pathname.new(ActiveRecord::Base.connection_db_config.database).expand_path
abort "QA exige o banco sintético tmp/p11-browser.sqlite3 em desenvolvimento." unless Rails.env.development? && actual == expected
abort "QA recusou uma conta que não pertence à fixture." if User.exists? && User.first.email_address != "browser@example.test"

require "securerandom"
require "tempfile"
password = SecureRandom.base64(24)
user = User.first || User.new(email_address: "browser@example.test")
user.update!(password: password, password_confirmation: password)
AuthSession.delete_all
Tempfile.create([ "p11-credentials", ".json" ], Rails.root.join("tmp")) do |file|
  file.chmod(0600)
  file.write(JSON.generate(email: user.email_address, password: password))
  file.flush
  file.fsync
  File.rename(file.path, Rails.root.join("tmp/p11-browser-credentials.json"))
end
puts "Fixture sintética preparada; credenciais aleatórias somente em rails/tmp ignorado."
