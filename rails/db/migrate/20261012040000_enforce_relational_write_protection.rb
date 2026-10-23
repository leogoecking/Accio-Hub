class EnforceRelationalWriteProtection < ActiveRecord::Migration[8.1]
  def up
    %w[projects tasks project_references focus_sessions user_preferences dock_shortcuts widget_placements].each do |table|
      immutable = [ "user_id" ]
      immutable << "uid" if %w[projects tasks project_references focus_sessions].include?(table)
      immutable += %w[project_id task_id] if table == "focus_sessions"
      immutable << "module_key" if table == "dock_shortcuts"
      immutable += %w[context project_id widget_key] if table == "widget_placements"
      trigger("#{table}_identity", "BEFORE UPDATE", table, immutable.map { |field| "NEW.#{field} IS NOT OLD.#{field}" }.join(" OR "), "Identidade e proprietário são imutáveis")
    end

    # Restore is the only allowed write to an archived project.
    preserved = %w[user_id uid name name_key description icon tint color favorite created_at origin_created_at origin_updated_at]
    restoration = "NEW.status = coalesce(OLD.archived_from, 'active') AND NEW.archived_from IS NULL AND NEW.archived_at IS NULL AND " + preserved.map { |field| "NEW.#{field} IS OLD.#{field}" }.join(" AND ")
    trigger("project_archived", "BEFORE UPDATE", "projects", "OLD.status = 'archived' AND NOT (#{restoration})", "Projeto arquivado é somente leitura")
    trigger("project_delete", "BEFORE DELETE", "projects", "1", "Use arquivamento")

    %w[tasks project_references widget_placements].each do |table|
      %w[INSERT UPDATE DELETE].each do |operation|
        ids = operation == "INSERT" ? [ "NEW" ] : operation == "DELETE" ? [ "OLD" ] : %w[OLD NEW]
        condition = ids.map { |row| "EXISTS (SELECT 1 FROM projects WHERE id = #{row}.project_id AND status = 'archived')" }.join(" OR ")
        trigger("#{table}_archived_#{operation.downcase}", "BEFORE #{operation}", table, condition, "Projeto arquivado é somente leitura")
      end
    end
    trigger("focus_archived_context", "BEFORE INSERT", "focus_sessions", "EXISTS (SELECT 1 FROM projects WHERE id = NEW.project_id AND status = 'archived')", "Restaure o projeto antes de iniciar novo foco")
    trigger("focus_task_context", "BEFORE INSERT", "focus_sessions", "NEW.task_id IS NOT NULL AND EXISTS (SELECT 1 FROM tasks WHERE id = NEW.task_id AND project_id IS NOT NEW.project_id)", "Contexto deve ser o da tarefa")
    lifecycle = "(NEW.status IN ('paused','awaiting_confirmation','completed','cancelled') OR (NEW.status = 'running' AND OLD.status = 'running')) AND NEW.duration_seconds IS OLD.duration_seconds AND NEW.started_at IS OLD.started_at AND NEW.created_at IS OLD.created_at"
    trigger("focus_archived_write", "BEFORE UPDATE", "focus_sessions", "EXISTS (SELECT 1 FROM projects WHERE id = OLD.project_id AND status = 'archived') AND NOT (#{lifecycle})", "Projeto arquivado permite apenas encerrar ou reconciliar foco existente")
    trigger("focus_terminal", "BEFORE UPDATE", "focus_sessions", "OLD.status IN ('completed','cancelled')", "Tentativa encerrada é imutável")
    trigger("focus_delete", "BEFORE DELETE", "focus_sessions", "1", "Tentativas de foco são preservadas")
    %w[UPDATE DELETE].each do |operation|
      trigger("command_immutable_#{operation.downcase}", "BEFORE #{operation}", "focus_commands", "1", "Recibo de comando é imutável")
    end
  end

  def down
    names = connection.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'accio_%'")
    names.each { |name| execute "DROP TRIGGER #{connection.quote_table_name(name)}" }
  end

  private

  def trigger(name, timing, table, condition, message)
    execute <<~SQL
      CREATE TRIGGER accio_#{name} #{timing} ON #{table}
      WHEN #{condition}
      BEGIN SELECT RAISE(ABORT, '#{message}'); END
    SQL
  end
end
