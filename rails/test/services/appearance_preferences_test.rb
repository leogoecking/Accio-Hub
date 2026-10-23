require "test_helper"

class AppearancePreferencesTest < ActiveSupport::TestCase
  setup do
    @user = synthetic_admin.first
    @store = AppearancePreferences.new(@user)
  end

  test "valid legacy appearance imports all rows and retains exact recovery" do
    value = Studio.defaults.merge("theme" => "light", "wallpaper" => "ember", "accent" => "#aabbcc", "music" => false, "musicExpanded" => true)
    value["dockOrder"].reverse!
    value["dockHidden"] = [ value["dockOrder"].first ]
    value["widgets"].reverse!
    value["widgets"].first.merge!("span" => 8, "visible" => false)
    state = @store.bootstrap(legacy: value, raw: "synthetic encrypted cookie")
    assert_equal value, state[:appearance]
    assert_equal 0, state[:version]
    preference = @user.user_preference
    assert_equal value, preference.legacy_cookie_backup["value"]
    assert_equal "synthetic encrypted cookie", preference.legacy_cookie_backup["raw"]
    assert preference.initialized_at
    assert preference.legacy_cookie_imported_at
    assert_equal 8, DockShortcut.count
    assert_equal 7, WidgetPlacement.count
  end

  test "missing cookie initializes once and rollback permits fresh retry" do
    WidgetPlacement.connection.execute("CREATE TRIGGER test_bootstrap_failure BEFORE INSERT ON widget_placements WHEN NEW.widget_key='focus' BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) { @store.bootstrap(legacy: nil, raw: nil) }
    assert_equal [ 0, 0, 0 ], [ UserPreference.count, DockShortcut.count, WidgetPlacement.count ]
    WidgetPlacement.connection.execute("DROP TRIGGER test_bootstrap_failure")
    assert_equal Studio.defaults, @store.bootstrap(legacy: nil, raw: nil)[:appearance]
    original = @user.user_preference.attributes
    @store.bootstrap(legacy: nil, raw: nil)
    assert_equal original, @user.user_preference.reload.attributes
  ensure
    WidgetPlacement.connection.execute("DROP TRIGGER IF EXISTS test_bootstrap_failure")
  end

  test "invalid incompatible and undecipherable cookies require explicit recovery" do
    [ nil, {}, Studio.defaults.merge("schema" => 99), Studio.defaults.merge("accent" => "red;") ].each do |value|
      assert_raises(AppearancePreferences::Invalid) { @store.bootstrap(legacy: value, raw: "broken cookie") }
      assert_equal 0, UserPreference.count
    end
    @store.bootstrap(legacy: {}, raw: "broken cookie", action: "use_defaults")
    assert_equal Studio.defaults, @store.read[:appearance]
    assert_equal({}, @user.user_preference.legacy_cookie_backup["value"])
  end

  test "another browser cannot overwrite SQLite with its legacy preferences" do
    @store.bootstrap(legacy: Studio.defaults, raw: "first cookie")
    value = Studio.defaults.merge("theme" => "light")
    @store.update(value, version: 0)
    original = @store.read
    other = Studio.defaults.merge("wallpaper" => "ocean")
    assert_raises(AppearancePreferences::LegacyConflict) { @store.bootstrap(legacy: other, raw: "second cookie") }
    assert_equal original, @store.read
    assert_raises(AppearancePreferences::Conflict) { @store.bootstrap(legacy: other, raw: "second cookie", action: "keep_database", version: 0) }
    state = @store.bootstrap(legacy: other, raw: "second cookie", action: "keep_database", version: 1)
    assert_equal value, state[:appearance]
    backup = @user.user_preference.reload.legacy_cookie_backup
    assert_equal Studio.defaults, backup["value"]
    assert_equal other, backup["retained_candidates"].values.first["value"]
  end

  test "equivalent legacy cookie is retained even when SQLite was initialized without a cookie" do
    @store.bootstrap(legacy: nil, raw: nil)
    result = @store.bootstrap(legacy: Studio.defaults, raw: "equivalent cookie")
    assert_equal Studio.defaults, result[:appearance]
    assert_equal Studio.defaults, @user.user_preference.reload.legacy_cookie_backup["retained_candidates"].values.first["value"]
  end

  test "whole aggregate rejects stale updates and preserves row identities" do
    @store.bootstrap(legacy: nil, raw: nil)
    dock_ids = DockShortcut.pluck(:module_key, :id).to_h
    widget_ids = WidgetPlacement.pluck(:widget_key, :id).to_h
    first = Studio.defaults.merge("theme" => "light")
    assert_equal 1, @store.update(first, version: 0)[:version]
    assert_raises(AppearancePreferences::Conflict) { @store.update(Studio.defaults, version: 0) }
    assert_equal first, @store.read[:appearance]
    first["dockOrder"].reverse!
    first["widgets"].reverse!
    first["widgets"].first["span"] = 12
    assert_equal 2, @store.update(first, version: 1)[:version]
    assert_equal dock_ids, DockShortcut.pluck(:module_key, :id).to_h
    assert_equal widget_ids, WidgetPlacement.pluck(:widget_key, :id).to_h
  end

  test "late update failure rolls back scalar version and all positions" do
    @store.bootstrap(legacy: nil, raw: nil)
    before = @store.read
    value = Studio.defaults.merge("theme" => "light")
    value["dockOrder"].reverse!
    value["widgets"].reverse!
    WidgetPlacement.connection.execute("CREATE TRIGGER test_save_failure BEFORE UPDATE ON widget_placements WHEN NEW.widget_key='tasks' BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END")
    assert_raises(ActiveRecord::StatementInvalid) { @store.update(value, version: 0) }
    assert_equal before, @store.read
  ensure
    WidgetPlacement.connection.execute("DROP TRIGGER IF EXISTS test_save_failure")
  end

  test "partial and future aggregates are rejected without repairing over old values" do
    @user.create_user_preference!(theme: "light")
    assert_raises(AppearancePreferences::Incompatible) { @store.bootstrap(legacy: nil, raw: nil) }
    assert_equal "light", @user.user_preference.reload.theme
    assert_equal 0, DockShortcut.count
  end
end
