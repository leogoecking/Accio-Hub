namespace :admin do
  desc "Reset the local administrator password interactively and revoke all sessions"
  task reset: :environment do
    require "io/console"

    abort "Use um terminal interativo para redefinir a senha." unless $stdin.tty?
    abort "Administrador não encontrado; nenhuma alteração realizada." unless User.exists?(1)

    print "Nova senha (mínimo 12 caracteres): "
    $stdout.flush
    password = $stdin.noecho(&:gets)
    puts
    abort "Entrada interrompida; nenhuma alteração realizada." unless password

    print "Confirme a nova senha: "
    $stdout.flush
    confirmation = $stdin.noecho(&:gets)
    puts
    abort "Entrada interrompida; nenhuma alteração realizada." unless confirmation

    AdminPasswordReset.call(password: password.chomp, confirmation: confirmation.chomp)
    puts "Senha redefinida. Todas as sessões anteriores foram revogadas."
  rescue ActiveRecord::RecordInvalid
    abort "Senha inválida ou confirmação diferente. A senha anterior e as sessões foram preservadas."
  rescue ActiveRecord::RecordNotFound
    abort "Administrador não encontrado; nenhuma alteração realizada."
  rescue ActiveRecord::ActiveRecordError
    abort "Falha no armazenamento. A redefinição foi cancelada; tente novamente."
  rescue Interrupt
    abort "Operação cancelada; nenhuma alteração realizada."
  end

  desc "Create the single local administrator from environment variables (no public registration)"
  task create: :environment do
    abort "Administrador já existe; nenhuma credencial foi alterada." if User.exists?
    email = ENV.fetch("ACCIO_ADMIN_EMAIL")
    password = ENV.fetch("ACCIO_ADMIN_PASSWORD")
    user = User.new(email_address: email, password: password, password_confirmation: password)
    unless user.save
      abort "Não foi possível criar o administrador. Confira e-mail e senha com pelo menos 12 caracteres."
    end
    puts "Administrador local criado."
  end
end
