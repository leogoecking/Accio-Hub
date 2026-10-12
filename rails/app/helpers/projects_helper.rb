module ProjectsHelper
  PROJECT_TINTS = { "mint" => "#8befcc", "purple" => "#c3b3ff", "pink" => "#ffbfce", "blue" => "#9fd4ff", "orange" => "#ffd8ad", "gold" => "#fcedb3" }.freeze
  PROJECT_ICONS = { "grid" => "Blocos", "code" => "Código", "book" => "Livro", "target" => "Foco", "rss" => "Feed", "calendar" => "Calendário", "cloud" => "Nuvem", "music" => "Música", "check" => "Tarefas", "mail" => "Carta" }.freeze
  PROJECT_STATUSES = { "active" => "Ativo", "paused" => "Pausado", "archived" => "Arquivado" }.freeze

  def project_color(project)
    project.color&.match?(/\A#[0-9a-f]{6}\z/i) ? project.color : PROJECT_TINTS.fetch(project.tint, PROJECT_TINTS.fetch("mint"))
  end

  def project_style(project)
    color = project_color(project)
    channels = color.delete_prefix("#").scan(/../).map do |value|
      channel = value.to_i(16) / 255.0
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
    ink = channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |c, weight| c * weight } > 0.179 ? "#101913" : "#ffffff"
    "--project-color:#{color};--project-ink:#{ink}"
  end

  def project_control(project, operation, label, values = {})
    render "projects/control", project: project, operation: operation, label: label, values: values
  end

  def safe_reference_url(url)
    parsed = URI.parse(url.to_s)
    url if parsed.is_a?(URI::HTTP) && parsed.host.present? && parsed.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end
end
