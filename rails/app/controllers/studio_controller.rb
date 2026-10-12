class StudioController < ApplicationController
  rescue_from AppearancePreferences::Invalid, AppearancePreferences::Incompatible, with: :invalid_preferences
  rescue_from AppearancePreferences::Conflict, ActiveRecord::StaleObjectError, with: :preference_conflict
  rescue_from AppearancePreferences::LegacyConflict, with: :legacy_conflict
  rescue_from ActiveRecord::StatementInvalid, with: :database_error

  def show
    @page = params.fetch(:page, "home")
    return head :not_found unless Studio::PAGES.include?(@page)
    return redirect_to projects_path if @page == "projects"
    load_studio
  end

  def load_studio
    @page ||= "projects"
    stored = preferences.read
    @appearance = stored ? stored[:appearance] : Studio.appearance(cookies.encrypted[:accio_appearance])
    @preference_version = stored ? stored[:version] : 0
    @bootstrap = stored.nil? || cookies[:accio_appearance].present?
  end

  def bootstrap
    result = preferences.bootstrap(legacy: cookies.encrypted[:accio_appearance], raw: cookies[:accio_appearance],
      action: params[:resolution], version: params[:version])
    cookies.delete(:accio_appearance, same_site: :strict, secure: request.ssl?)
    presentation_cookie(result[:appearance])
    render json: result
  end

  def appearance
    result = preferences.update(params.require(:appearance).to_unsafe_h, version: params[:version])
    presentation_cookie(result[:appearance])
    render json: result
  end

  private

  def preferences
    @preferences ||= AppearancePreferences.new(Current.user)
  end

  def invalid_preferences(error)
    render json: { error: "invalid_preferences", message: error.message,
      recovery: preferences.legacy_candidate(cookies.encrypted[:accio_appearance], cookies[:accio_appearance]),
      allow_defaults: action_name == "bootstrap" && !Current.user.user_preferences_scope.exists? }, status: :unprocessable_entity
  end

  def preference_conflict(_error)
    render json: preferences.read.merge(error: "conflict", message: "Outra aba salvou preferências. Sua edição local foi mantida."), status: :conflict
  end

  def legacy_conflict(error)
    render json: preferences.read.merge(error: "legacy_conflict", message: error.message,
      recovery: preferences.legacy_candidate(cookies.encrypted[:accio_appearance], cookies[:accio_appearance])), status: :conflict
  end

  def database_error(error)
    raise error unless error.cause.is_a?(SQLite3::BusyException) || error.cause.is_a?(SQLite3::LockedException)
    render json: { error: "database_busy", message: "O armazenamento está ocupado. Sua edição foi mantida; tente novamente." }, status: :service_unavailable
  end

  def presentation_cookie(appearance)
    cookies.encrypted[:accio_presentation] = {
      value: appearance.slice("theme", "wallpaper", "accent"), expires: 1.year.from_now,
      httponly: true, same_site: :strict, secure: request.ssl?
    }
  end
end
