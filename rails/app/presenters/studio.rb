class Studio
  # Synthetic presentation data, never an operational projects/tasks/notes store.
  DATA = JSON.parse(File.read(Rails.root.join("config/studio_fixture.json"))).freeze
  NAV = DATA.fetch("nav").freeze
  DOCK = DATA.fetch("dock").freeze
  WIDGETS = DATA.fetch("widgets").freeze
  LABELS = DATA.fetch("labels").freeze
  PAGES = LABELS.keys.freeze

  def self.defaults
    { "theme" => "dark", "wallpaper" => "northern", "accent" => "#b1f07d",
      "music" => true, "musicExpanded" => false,
      "dockOrder" => DOCK.map(&:first), "dockHidden" => [],
      "widgets" => WIDGETS.map { |id, w| { "id" => id, "span" => w.fetch("span"), "visible" => true } } }
  end

  def self.appearance(value)
    return defaults unless value.is_a?(Hash)
    result = defaults
    result["theme"] = value["theme"] if %w[dark light].include?(value["theme"])
    result["wallpaper"] = value["wallpaper"] if %w[northern ember ocean graphite].include?(value["wallpaper"])
    result["accent"] = value["accent"] if value["accent"].is_a?(String) && value["accent"].match?(/\A#[0-9a-f]{6}\z/i)
    %w[music musicExpanded].each { |key| result[key] = value[key] if [ true, false ].include?(value[key]) }
    ids = DOCK.map(&:first)
    order = value["dockOrder"]
    result["dockOrder"] = order if order.is_a?(Array) && order.all?(String) && order.sort == ids.sort
    hidden = value["dockHidden"]
    result["dockHidden"] = hidden.uniq & ids if hidden.is_a?(Array)
    widgets = value["widgets"]
    if widgets.is_a?(Array) && widgets.all? { |w| w.is_a?(Hash) && w["id"].is_a?(String) } && widgets.map { |w| w["id"] }.sort == WIDGETS.keys.sort
      result["widgets"] = widgets.map do |w|
        { "id" => w["id"], "span" => [ 3, 4, 5, 6, 8, 12 ].include?(w["span"]) ? w["span"] : WIDGETS[w["id"]]["span"],
          "visible" => [ true, false ].include?(w["visible"]) ? w["visible"] : true }
      end
    end
    result
  end
end
