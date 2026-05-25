# frozen_string_literal: true

module SkpToMax
  module BoundaryStore
    DICT        = 'skp_to_max'
    KEY_CHECKED = 'checked'
    KEY_PATH    = 'persistent_id_path'

    class << self
      # Writes checked status and a fresh persistent_id_path onto the entity.
      # Wraps in a SketchUp operation so any mid-write failure aborts cleanly.
      def set(entity, checked: true)
        model = entity.model
        return if model.nil?

        model.start_operation('BoundaryStore.set', true)
        begin
          path = build_path(entity)
          dict = entity.attribute_dictionary(DICT, true)
          dict[KEY_CHECKED] = checked
          dict[KEY_PATH]    = path
          model.commit_operation
        rescue => e
          model.abort_operation
          raise e
        end
      end

      # Returns true/false from stored attribute, or nil if no data present
      # (treat nil as unchecked — do not assume false).
      def checked?(entity)
        dict = entity.attribute_dictionary(DICT)
        return nil if dict.nil?

        val = dict[KEY_CHECKED]
        val.nil? ? nil : val
      end

      # Returns the stored persistent_id_path array, or nil if not yet set.
      def get_path(entity)
        dict = entity.attribute_dictionary(DICT)
        return nil if dict.nil?

        dict[KEY_PATH]
      end

      # Removes the skp_to_max attribute dictionary entirely from the entity.
      def clear(entity)
        entity.delete_attribute(DICT)
      end

      # Walks the entire model entity tree and returns every entity whose
      # checked? value is exactly true (not just truthy — nil is excluded).
      def all_checked(model)
        results = []
        walk_entities(model.entities, results, {})
        results
      end

      private

      # Builds root-to-leaf array of persistent_id integers by walking up
      # from entity through parent drawing contexts to the model root.
      # Built fresh on every call — never cached (entity may have moved).
      # Handles entities with no parent without raising.
      def build_path(entity)
        ids = []
        cur = entity

        loop do
          break unless cur.respond_to?(:persistent_id)

          ids.unshift(cur.persistent_id)

          ctx = cur.respond_to?(:parent) ? cur.parent : nil
          break if ctx.nil? || !ctx.respond_to?(:parent)

          owner = ctx.parent
          break if owner.nil? || owner.is_a?(Sketchup::Model)
          break unless owner.respond_to?(:instances)

          instances = owner.instances
          break if instances.empty?

          # For unique components/groups there is exactly one instance;
          # for shared definitions we take the first occurrence — the path
          # is a best-effort snapshot and is validated on export (guardrail #4).
          cur = instances.first
        end

        ids
      end

      # Recursive walk through an Entities collection.
      # Visits each definition at most once (via visited_defs) to avoid
      # processing shared-component contents multiple times.
      def walk_entities(entities, results, visited_defs)
        entities.each do |entity|
          results << entity if checked?(entity) == true

          if entity.is_a?(Sketchup::Group)
            walk_entities(entity.entities, results, visited_defs)
          elsif entity.is_a?(Sketchup::ComponentInstance)
            defn = entity.definition
            pid  = defn.persistent_id
            next if visited_defs[pid]

            visited_defs[pid] = true
            walk_entities(defn.entities, results, visited_defs)
          end
        end
      end
    end
  end
end
