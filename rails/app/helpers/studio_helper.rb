module StudioHelper
  def studio_path(page)
    return projects_path if page == "projects"
    page == "home" ? root_path : app_path(page: page)
  end

  def studio_icon(name, size = 20)
    # Only checked-in synthetic icon paths, never request content.
    paths = Studio::DATA.fetch("icons").fetch(name.to_s, Studio::DATA.fetch("icons").fetch("grid"))
    content_tag(:svg, paths.html_safe, width: size, height: size, viewBox: "0 0 24 24",
      "aria-hidden": true, fill: "none", stroke: "currentColor", "stroke-width": "1.7",
      "stroke-linecap": "round", "stroke-linejoin": "round")
  end
end
