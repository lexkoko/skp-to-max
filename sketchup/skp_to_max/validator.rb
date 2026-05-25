# frozen_string_literal: true

require_relative 'boundary_store'

module SkpToMax
  module Validator

    ValidationResult = Struct.new(
      :valid,       # true | false
      :stale_paths, # Array<Array<Integer>> — stored paths that no longer resolve
      :warnings,    # Array<String>         — human-readable descriptions per stale path
      :summary,     # String                — single-line result for UI / logging
      keyword_init: true
    )

    class << self

      # Implements guardrail #4 from policy.md:
      #   "validate before every export: every persistent_id in manifest
      #    must resolve to a live entity"
      #
      # Algorithm:
      #   1. Collect all checked entities via BoundaryStore.all_checked(model)
      #   2. For each entity retrieve its stored persistent_id_path
      #   3. Walk the path from model.entities, matching each integer via
      #      persistent_id at each nesting level
      #   4. If any step in the walk fails → path is stale
      #
      # Returns a ValidationResult. Call clear_stale(model) to remove entries
      # that no longer resolve, then re-check boundaries before retrying export.
      #
      # ── Known limitations ──────────────────────────────────────────────────
      #
      # (a) Two-level deep shared-component nesting:
      #     BoundaryStore.build_path traverses upward taking instances.first at
      #     each ComponentDefinition boundary. If SharedDefOuter has placements
      #     at different hierarchy depths (e.g. one directly in model.entities
      #     and one inside another group), the stored path may route through a
      #     DIFFERENT placement than the one the user actually placed the entity
      #     in. The path walk will still SUCCEED (the entity exists at that
      #     location via instances.first), so validate() reports :valid => true.
      #     Consequence: the path is technically live but may reference the wrong
      #     occurrence. A multi-placement structural audit is deferred to a
      #     future pass.
      #
      # (b) Case-8 false-positive (occurrence override):
      #     DefinitionResolver classifies a checked entity as case #8 whenever
      #     exactly 1 of N instances of a shared definition is checked. If the
      #     user checks only 1 occurrence without intending an override (they
      #     simply haven't checked the others yet), the resolver will still flag
      #     it as case #8 and require make-unique in staging. validate() cannot
      #     detect this intent mismatch — it only verifies path liveness. The UI
      #     layer should warn when a single occurrence of a multi-instance
      #     definition is checked (not yet implemented).
      def validate(model)
        checked  = BoundaryStore.all_checked(model)
        stale    = []
        warnings = []

        checked.each do |entity|
          path = BoundaryStore.get_path(entity)

          if path.nil? || path.empty?
            stale    << [entity.persistent_id]
            warnings << "Entity pid=#{entity.persistent_id} has no stored path — " \
                        "re-run BoundaryStore.set to record its current location"
            next
          end

          next if path_resolves?(path, model)

          stale    << path
          warnings << "Stale path #{path.inspect} — parent hierarchy changed " \
                      "(entity moved, ancestor deleted/recreated, or group exploded)"
        end

        n_stale = stale.size

        if n_stale.zero?
          summary = checked.empty? ? "OK: no boundaries set" \
                                   : "OK: #{checked.size} #{checked.size == 1 ? 'boundary' : 'boundaries'} valid"
        else
          summary = "FAIL: #{n_stale} stale #{n_stale == 1 ? 'boundary' : 'boundaries'} found — clear and re-check"
        end

        ValidationResult.new(
          valid:       n_stale.zero?,
          stale_paths: stale,
          warnings:    warnings,
          summary:     summary
        )
      end

      # Removes all boundary entries whose stored path no longer resolves.
      # Leaves every valid entry untouched.
      #
      # Wraps all BoundaryStore.clear calls in a single staging-abort operation
      # so the model is never left partially cleared if anything raises mid-pass.
      def clear_stale(model)
        model.start_operation('Validator.clear_stale', true)
        begin
          checked = BoundaryStore.all_checked(model)
          checked.each do |entity|
            path  = BoundaryStore.get_path(entity)
            stale = path.nil? || path.empty? || !path_resolves?(path, model)
            BoundaryStore.clear(entity) if stale
          end
          model.commit_operation
        rescue => e
          model.abort_operation
          raise e
        end
      end

      private

      # Walks the stored persistent_id_path from model.entities downward.
      # At each step, searches the current drawing context for an entity whose
      # persistent_id matches the next integer in the path, then descends into
      # that entity's children. Returns true only when every id resolves.
      def path_resolves?(path, model)
        ctx = model.entities

        path.each_with_index do |pid, idx|
          entity = find_by_pid(ctx, pid)
          return false if entity.nil?

          # Advance into children for the next step; last step needs no descent.
          if idx < path.length - 1
            ctx = children_of(entity)
            return false if ctx.nil?
          end
        end

        true
      end

      # Linear scan of an Entities collection for a specific persistent_id.
      def find_by_pid(entities, pid)
        entities.find { |e| e.persistent_id == pid }
      end

      # Returns the Entities collection directly accessible inside a container.
      # Groups expose their own entities; ComponentInstances expose their
      # shared definition's entities. Returns nil for non-container entity types.
      def children_of(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.respond_to?(:definition)
          entity.definition.entities
        end
      end

    end
  end
end
