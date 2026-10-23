#!/usr/bin/env ruby
require "bundler/setup"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "sqlite3"

rails_root = File.expand_path("../../../../../rails", __dir__)
output_dir = File.expand_path(__dir__)

require_relative File.join(rails_root, "app/services/sqlite_backup_snapshot")

Dir.mktmpdir("accio-f5-diff-") do |dir|
  test_db = File.join(dir, "test.sqlite3")
  dev_db = File.join(dir, "dev.sqlite3")

  Open3.capture3({ "RAILS_ENV" => "test", "ACCIO_DATABASE_PATH" => test_db, "SECRET_KEY_BASE" => SecureRandom.hex(64) }, "bin/rails", "db:schema:load", chdir: rails_root)
  Open3.capture3({ "RAILS_ENV" => "development", "ACCIO_DATABASE_PATH" => dev_db, "SECRET_KEY_BASE" => SecureRandom.hex(64) }, "bin/rails", "db:schema:load", chdir: rails_root)

  db_test = SQLite3::Database.new(test_db, readonly: true)
  db_dev = SQLite3::Database.new(dev_db, readonly: true)

  test_schema = SqliteBackupSnapshot.schema(db_test)
  dev_schema = SqliteBackupSnapshot.schema(db_dev)

  test_objects = test_schema["objects"]
  dev_objects = dev_schema["objects"]

  puts "Total objects in test: #{test_objects.size}"
  puts "Total objects in dev:  #{dev_objects.size}"

  diffs = []
  test_objects.each_with_index do |t_row, idx|
    d_row = dev_objects[idx]
    if t_row != d_row
      # compare element by element: [type, name, tbl_name, sql]
      t_type, t_name, t_tbl, t_sql = t_row
      d_type, d_name, d_tbl, d_sql = d_row

      type_match = (t_type == d_type)
      name_match = (t_name == d_name)
      tbl_match = (t_tbl == d_tbl)

      # Check if diff in SQL is EXACTLY the trailing comment
      tag = " /*application='AccioHub'*/"
      ends_with_tag = d_sql&.end_with?(tag)
      sql_without_tag = ends_with_tag ? d_sql.delete_suffix(tag) : d_sql
      sql_matches_after_tag_removal = (t_sql == sql_without_tag)

      diffs << {
        index: idx,
        type: t_type,
        name: t_name,
        table: t_tbl,
        metadata_match: (type_match && name_match && tbl_match),
        ends_with_expected_tag: ends_with_tag,
        sql_matches_after_tag_removal: sql_matches_after_tag_removal,
        test_sql_length: t_sql&.length,
        dev_sql_length: d_sql&.length,
        diff_exact_length: (d_sql&.length.to_i - t_sql&.length.to_i),
        expected_tag_length: tag.length,
        test_sql: t_sql,
        dev_sql: d_sql
      }
    end
  end

  # Compare foreign_keys structure
  fk_match = (test_schema["foreign_keys"] == dev_schema["foreign_keys"])
  puts "Foreign keys match exactly: #{fk_match}"
  puts "Objects with differences: #{diffs.size}"
  puts "Objects where diff is STRICTLY the query log tag: #{diffs.count { |d| d[:sql_matches_after_tag_removal] }}"

  comparison_data = {
    test_objects_count: test_objects.size,
    dev_objects_count: dev_objects.size,
    foreign_keys_match_exactly: fk_match,
    total_differences_count: diffs.size,
    strictly_tag_differences_count: diffs.count { |d| d[:sql_matches_after_tag_removal] },
    all_differences_strictly_tag: (diffs.size == diffs.count { |d| d[:sql_matches_after_tag_removal] }),
    diffs_summary: diffs.map { |d| { type: d[:type], name: d[:name], table: d[:table], ends_with_expected_tag: d[:ends_with_expected_tag], matches_when_removed: d[:sql_matches_after_tag_removal] } },
    detailed_diffs: diffs
  }

  output_file = File.join(output_dir, "sql_literal_diff.json")
  File.write(output_file, JSON.pretty_generate(comparison_data) + "\n")
  puts "Detailed diff saved to: #{output_file}"

  db_test.close
  db_dev.close
end
