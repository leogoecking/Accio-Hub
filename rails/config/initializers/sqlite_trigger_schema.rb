require "active_record/connection_adapters/sqlite3_adapter"
require "active_record/connection_adapters/sqlite3/schema_dumper"

# Rails' Ruby SQLite dump omits triggers. Preserve our checked-in integrity
# rules in schema.rb so schema:load and test databases enforce the same rules.
module SQLiteTriggerSchema
  private

  def tables(stream)
    super
    triggers = @connection.select_values("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'accio_%' ORDER BY name")
    triggers.each { |sql| stream.puts "  execute #{sql.inspect}" }
  end
end

ActiveRecord::ConnectionAdapters::SQLite3::SchemaDumper.prepend(SQLiteTriggerSchema)
