#!/usr/bin/env ruby
# Creates only NEW private synthetic databases and cookie fixtures for browser QA.
require "tmpdir"
require "open3"
require "fileutils"
root = File.expand_path("..", __dir__)
directory = Dir.mktmpdir("p12d-browser-", File.join(root, "tmp"))
setup = File.join(directory, "setup.rb")
File.write(setup, <<~'RUBY')
  require "json"
  Rails.logger.level = Logger::WARN
  directory=ENV.fetch("P12C_WORKSPACE")
  path=File.join(directory,"credentials.json")
  if File.exist?(path)
    value=JSON.parse(File.read(path))
    User.create!(email_address:value.fetch("email"),password:value.fetch("password"))
  else
    password=SecureRandom.hex(20)
    User.create!(email_address:"qa@example.test",password:password)
    request=ActionDispatch::Request.new(Rails.application.env_config.merge("HTTP_HOST"=>"127.0.0.1:3122","rack.url_scheme"=>"http"))
    jar=ActionDispatch::Cookies::CookieJar.build(request,{})
    jar.encrypted[:accio_appearance]={value:Studio.defaults,httponly:true,same_site: :strict}
    File.write(path,JSON.generate({email:"qa@example.test",password:password,legacy:URI.encode_www_form_component(jar[:accio_appearance])}),mode:"w",perm:0o600)
    jar.encrypted[:accio_appearance]={value:Studio.defaults.merge("wallpaper"=>"ember","accent"=>"#aa3399"),httponly:true,same_site: :strict}
    File.write(File.join(directory,"other-cookie.json"),JSON.generate({value:URI.encode_www_form_component(jar[:accio_appearance])}),mode:"w",perm:0o600)
  end
RUBY
%w[synthetic empty].each do |name|
  env={ "RAILS_ENV"=>"development", "ACCIO_DATABASE_PATH"=>File.join(directory, "#{name}.sqlite3"), "P12C_WORKSPACE"=>directory }
  [ [ "bin/rails", "db:schema:load" ], [ "bin/rails", "runner", setup ] ].each do |command|
    output, errors, status=Open3.capture3(env, *command, chdir: root)
    raise "Synthetic setup failed: #{errors} #{output[-1000..]}" unless status.success?
  end
end
File.write(File.join(root, "tmp/p12d-workspace"), directory+"\n")
puts "Synthetic workspace: #{directory}"
