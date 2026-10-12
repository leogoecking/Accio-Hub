class StudioController < ApplicationController
  def show
    @page = params.fetch(:page, "home")
    return head :not_found unless Studio::PAGES.include?(@page)
    @appearance = Studio.appearance(cookies.encrypted[:accio_appearance])
  end

  def appearance
    preferences = Studio.appearance(params.require(:appearance).permit(
      :theme, :wallpaper, :accent, :music, :musicExpanded,
      dockOrder: [], dockHidden: [], widgets: [ :id, :span, :visible ]
    ).to_h)
    cookies.encrypted[:accio_appearance] = {
      value: preferences, expires: 1.year.from_now, httponly: true,
      same_site: :strict, secure: request.ssl?
    }
    render json: { appearance: preferences }
  end
end
