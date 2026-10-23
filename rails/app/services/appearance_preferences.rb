require "digest"

# One transaction and one version for the appearance/Dock/home-widget aggregate.
class AppearancePreferences
  class Invalid < StandardError; end
  class Incompatible < StandardError; end
  class Conflict < StandardError; end
  class LegacyConflict < StandardError; end

  def initialize(user)
    @user = user
  end

  def self.validate!(value)
    raise Invalid, "Formato de preferências incompatível" unless value.is_a?(Hash) && value.keys.sort == Studio.defaults.keys.sort
    raise Invalid, "Preferências inválidas; o conteúdo original foi preservado" unless Studio.appearance(value) == value
    value.deep_dup
  end

  def read
    aggregate_transaction do
      preference = @user.user_preferences_scope.first
      preference && snapshot(preference)
    end
  end

  def bootstrap(legacy:, raw:, action: nil, version: nil)
    candidate = legacy_candidate(legacy, raw)
    aggregate_transaction do
      preference = @user.user_preferences_scope.first
      if preference
        current = snapshot(preference)
        if raw && candidate["digest"] != preference.legacy_cookie_digest
          if candidate["value"] != current[:appearance]
            raise LegacyConflict, "Preferências antigas deste navegador diferem do banco" unless action == "keep_database"
            check_version!(preference, version)
          end
          backup = (preference.legacy_cookie_backup || {}).deep_dup
          retained = backup.fetch("retained_candidates", {})
          retained[candidate.fetch("digest")] = candidate
          preference.update!(legacy_cookie_backup: backup.merge("retained_candidates" => retained))
        end
      else
        raise Incompatible, "Organização existente sem preferências inicializadas" if @user.dock_shortcuts.exists? || @user.widget_placements.where(context: "home").exists?
        raise Invalid, "Cookie antigo inválido ou incompatível; revise antes de inicializar" if raw && !candidate["valid"] && action != "use_defaults"
        value = candidate["valid"] ? candidate["value"] : Studio.defaults
        preference = UserPreference.create!(scalar_attributes(value).merge(user: @user,
          initialized_at: Time.current, legacy_cookie_imported_at: raw ? Time.current : nil,
          legacy_cookie_digest: candidate["digest"], legacy_cookie_backup: raw ? candidate : nil))
        value.fetch("dockOrder").each_with_index do |key, i|
          @user.dock_shortcuts.create!(module_key: key, position: i, visible: !value.fetch("dockHidden").include?(key))
        end
        value.fetch("widgets").each_with_index do |widget, i|
          @user.widget_placements.create!(context: "home", widget_key: widget.fetch("id"), span: widget.fetch("span"), visible: widget.fetch("visible"), position: i)
        end
      end
      snapshot(preference)
    end
    # Fresh read after commit, before the controller retires the cookie.
    read || raise(Incompatible, "Inicialização não confirmada")
  end

  def update(value, version:)
    value = self.class.validate!(value)
    aggregate_transaction do
      preference = @user.user_preferences_scope.first || raise(Incompatible, "Inicialize suas preferências antes de salvar")
      snapshot(preference)
      check_version!(preference, version)
      preference.update!(scalar_attributes(value))
      preference.touch if preference.lock_version == version
      reorder_and_update(@user.dock_shortcuts, "module_key", value.fetch("dockOrder")) do |row|
        { visible: !value.fetch("dockHidden").include?(row.module_key) }
      end
      widgets = value.fetch("widgets").index_by { |w| w.fetch("id") }
      reorder_and_update(@user.widget_placements.where(context: "home"), "widget_key", widgets.keys) do |row|
        widgets.fetch(row.widget_key).slice("span", "visible")
      end
      snapshot(preference)
    end
  end

  def legacy_candidate(legacy, raw)
    return { "valid" => false } unless raw
    valid = begin
      self.class.validate!(legacy)
      true
    rescue Invalid
      false
    end
    { "source" => "p1.1-cookie", "digest" => Digest::SHA256.hexdigest(raw),
      "valid" => valid, "value" => legacy, "raw" => raw }
  end

  private

  def aggregate_transaction(&block)
    # Each command needs a fresh snapshot, including a missing singleton during bootstrap.
    UserPreference.uncached do
      UserPreference.transaction do
        UserPreference.connection.materialize_transactions
        block.call
      end
    end
  end

  def check_version!(preference, version)
    raise Conflict, "A aparência foi alterada em outra aba" unless version.is_a?(Integer) && version == preference.lock_version
  end

  def snapshot(preference)
    dock = @user.dock_shortcuts.order(:position).to_a
    widgets = @user.widget_placements.where(context: "home").order(:position).to_a
    unless preference.initialized_at && preference.preferences_schema_version == 1 &&
        dock.map(&:module_key).sort == Studio::DOCK.map(&:first).sort &&
        widgets.map(&:widget_key).sort == Studio::WIDGETS.keys.sort &&
        dock.map(&:position) == (0...dock.size).to_a && widgets.map(&:position) == (0...widgets.size).to_a
      raise Incompatible, "Preferências incompletas ou de versão incompatível; nenhum registro foi substituído"
    end
    { version: preference.lock_version, appearance: {
      "theme" => preference.theme, "wallpaper" => preference.wallpaper, "accent" => preference.accent,
      "music" => preference.music_enabled, "musicExpanded" => preference.music_expanded,
      "dockOrder" => dock.map(&:module_key), "dockHidden" => dock.reject(&:visible).map(&:module_key),
      "widgets" => widgets.map { |w| { "id" => w.widget_key, "span" => w.span, "visible" => w.visible } }
    } }
  end

  def scalar_attributes(value)
    { theme: value.fetch("theme"), wallpaper: value.fetch("wallpaper"), accent: value.fetch("accent"),
      music_enabled: value.fetch("music"), music_expanded: value.fetch("musicExpanded") }
  end

  def reorder_and_update(scope, key, keys)
    rows = scope.order(:position).to_a
    if rows.map { |row| row.public_send(key) } != keys
      rows.each_with_index { |row, i| row.update!(position: rows.size * 2 + i) }
    end
    keys.each_with_index do |id, i|
      row = rows.find { |item| item.public_send(key) == id }
      row.update!(yield(row).merge(position: i))
    end
  end
end
