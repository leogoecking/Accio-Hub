if Rails.env.production? && ENV["ACCIO_DATABASE_PATH"].blank?
  raise "Defina ACCIO_DATABASE_PATH fora do checkout para executar em produção."
end
