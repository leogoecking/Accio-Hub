class ApplicationController < ActionController::Base
  include Authentication
  before_action :disable_private_cache

  private

  def disable_private_cache
    response.headers["Cache-Control"] = "no-store"
  end
end
