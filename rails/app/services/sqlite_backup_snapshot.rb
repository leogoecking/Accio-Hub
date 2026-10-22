require "base64"
require "digest"
require "json"

# Fingerprints contain every row, including SQLite sequences, without exporting row values.
module SqliteBackupSnapshot
  def self.schema(db)
    objects = db.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
    tables = objects.select { |row| row[0] == "table" }.map { |row| row[1] }.sort
    foreign_keys = tables.to_h do |table|
      groups = db.execute("PRAGMA foreign_key_list(#{quote(table)})").group_by(&:first).values
      [ table, groups.map { |rows| rows.sort_by { |row| row[1] }.map { |row| row.drop(1) } }.sort_by { |rows| JSON.generate(rows) } ]
    end
    { "objects" => objects, "foreign_keys" => foreign_keys }
  end

  def self.read(db)
    structure = schema(db)
    tables = structure.fetch("objects").select { |row| row[0] == "table" }.map { |row| row[1] }.sort
    fingerprints = tables.to_h do |table|
      columns = db.execute("PRAGMA table_xinfo(#{quote(table)})")
      count = 0
      digest = Digest::SHA256.new
      db.execute("SELECT * FROM #{quote(table)} ORDER BY #{(1..columns.size).to_a.join(',')}") do |row|
        # Type tags and Base64 preserve text/BLOB bytes; float bits are not reformatted.
        values = row.map do |value|
          case value
          when String then [ value.is_a?(SQLite3::Blob) ? "blob" : "text", Base64.strict_encode64(value.b) ]
          when Float then [ "float", [ value ].pack("G").unpack1("H*") ]
          else [ value.class.name, value ]
          end
        end
        digest.update(JSON.generate(values) + "\n")
        count += 1
      end
      [ table, { "columns" => columns, "rows" => count, "sha256" => digest.hexdigest } ]
    end
    { "schema" => structure, "schema_sha256" => fingerprint(structure), "tables" => fingerprints }
  end

  def self.fingerprint(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  def self.quote(identifier)
    '"' + identifier.gsub('"', '""') + '"'
  end
end
