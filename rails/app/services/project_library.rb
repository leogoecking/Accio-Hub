class ProjectLibrary
  FILTERS = %w[project_library_status project_library_sort project_library_favorites_only].freeze

  def initialize(user)
    @user = user
  end

  def filters
    @user.user_preferences_scope.first&.attributes&.slice(*FILTERS) || {
      "project_library_status" => "all", "project_library_sort" => "name", "project_library_favorites_only" => false
    }
  end

  def update_filters(attributes, version:)
    UserPreference.uncached do
      UserPreference.transaction do
        UserPreference.connection.materialize_transactions
        AppearancePreferences.new(@user).read || raise(AppearancePreferences::Incompatible, "Inicialize suas preferências antes de filtrar")
        preference = @user.user_preferences_scope.first!
        raise AppearancePreferences::Conflict unless version.is_a?(Integer) && preference.lock_version == version
        preference.update!(attributes.slice(*FILTERS))
        preference.touch if preference.lock_version == version
        { filters: preference.attributes.slice(*FILTERS) }.merge(AppearancePreferences.new(@user).read)
      end
    end
  end

  def select(search: "")
    selection = @user.projects
    value = filters
    selection = selection.where(status: value.fetch("project_library_status")) unless value.fetch("project_library_status") == "all"
    selection = selection.where(favorite: true) if value.fetch("project_library_favorites_only")
    term = fold(search.to_s.strip)
    rows = selection.to_a.select { |p| term.empty? || fold("#{p.name} #{p.description}").include?(term) }
    if value.fetch("project_library_sort") == "recent"
      rows.sort_by { |p| [ -(p.last_activity_at || p.origin_updated_at || p.created_at).to_f, natural(p.name), p.uid ] }
    else
      rows.sort_by { |p| [ natural(p.name), p.uid ] }
    end
  end

  private

  def fold(value)
    value.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase
  end

  def natural(value)
    fold(value).split(/(\d+)/).map { |part| part.match?(/\A\d+\z/) ? [ 0, part.to_i ] : [ 1, part ] }
  end
end
