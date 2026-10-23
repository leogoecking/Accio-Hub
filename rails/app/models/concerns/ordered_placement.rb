module OrderedPlacement
  extend ActiveSupport::Concern

  class_methods do
    private

    def reorder_scope!(user:, scope:, key:, keys:, expected_version:)
      transaction do
        preference = user.user_preference || raise(ActiveRecord::RecordNotFound, "Preferências não inicializadas")
        preference.reload
        raise ActiveRecord::StaleObjectError.new(preference, "reorder") unless preference.lock_version == expected_version
        records = scope.order(:position).to_a
        unless keys.is_a?(Array) && keys.all?(String) && keys.uniq.size == keys.size && keys.sort == records.map { |r| r.public_send(key) }.sort
          raise ArgumentError, "Ordem deve conter todos os registros, uma única vez"
        end

        preference.touch
        offset = (records.map(&:position).max || 0) + records.size + 1
        records.each_with_index { |record, i| record.update!(position: offset + i) }
        keys.each_with_index { |value, i| records.find { |record| record.public_send(key) == value }.update!(position: i) }
        scope.order(:position).to_a
      end
    end
  end
end
