# frozen_string_literal: true

require_relative 'boundary_store'

module SkpToMax
  module DefinitionResolver

    # One entry per entity placement in the resolved result.
    # :depth_level (0 = top-level) is required by BODY-sweep (case #3) to
    # locate the nearest checked ancestor without a second model walk.
    ResolvedEntry = Struct.new(
      :entity,         # Sketchup::Entity — the specific placement
      :kind,           # :unique | :shared
      :definition,     # Sketchup::ComponentDefinition | nil  (nil for Groups)
      :instance_count, # Integer — total placements of this definition
      :merge_key,      # String — groups same-output entities together
      :case_number,    # Integer 1–8 per policy.md table
      :depth_level,    # Integer — 0 = directly in model.entities
      keyword_init: true
    )

    class << self

      # Classifies every entity in the checked set according to the 8-case
      # policy table and returns one ResolvedEntry per entity placement.
      #
      # For shared definitions, ALL instance placements are included in the
      # result (not only the checked ones) so downstream code sees every SM_
      # slot without a second model walk.
      #
      # entities - Array<Sketchup::Entity> from BoundaryStore.all_checked()
      # model    - Sketchup::Model (currently unused; reserved for future
      #            top-level enumeration pass for cases 3 & 4)
      def resolve(entities, model)
        entity_pid_set   = entities.each_with_object({}) { |e, h| h[e.persistent_id] = true }
        visited_def_pids = {}
        result           = []

        entities.each do |entity|
          # Only Groups and ComponentInstances carry boundary & definition data.
          next unless entity.respond_to?(:definition)

          defn       = entity.definition
          inst_count = defn.instances.count

          if entity.is_a?(Sketchup::Group) || inst_count == 1
            # Groups always unique; single-placement components are unique by count.
            result << build_unique_entry(entity, defn, entity_pid_set)
          else
            # Shared definition — emit entries for ALL placements exactly once.
            defn_pid = defn.persistent_id
            next if visited_def_pids[defn_pid]
            visited_def_pids[defn_pid] = true

            all_insts             = defn.instances
            has_checked_def_child = any_checked_in_def?(defn)
            checked_count         = all_insts.count { |i| entity_pid_set[i.persistent_id] }
            key                   = merge_key_for_shared(defn)

            all_insts.each do |inst|
              is_checked = entity_pid_set[inst.persistent_id] ? true : false
              cn = assign_case_shared(is_checked, has_checked_def_child,
                                      checked_count, all_insts.count)
              result << ResolvedEntry.new(
                entity:         inst,
                kind:           :shared,
                definition:     defn,
                instance_count: inst_count,
                merge_key:      key,
                case_number:    cn,
                depth_level:    compute_depth(inst)
              )
            end
          end
        end

        result
      end

      private

      # Builds a :unique ResolvedEntry. Case 1 when any descendant is checked
      # (this node becomes an A_ actor/container); case 2 when it's a leaf.
      def build_unique_entry(entity, defn, entity_pid_set)
        inner     = entity.is_a?(Sketchup::Group) ? entity.entities : defn.entities
        has_child = any_checked_descendant?(inner, entity_pid_set)

        ResolvedEntry.new(
          entity:         entity,
          kind:           :unique,
          definition:     entity.is_a?(Sketchup::Group) ? nil : defn,
          instance_count: 1,
          merge_key:      entity.persistent_id.to_s,
          case_number:    has_child ? 1 : 2,
          depth_level:    compute_depth(entity)
        )
      end

      # Recursive descent: true if any entity in this subtree appears in the
      # checked set. Used to distinguish case 1 (A_ actor) from case 2 (SM_ leaf).
      def any_checked_descendant?(container_entities, entity_pid_set)
        container_entities.any? do |child|
          next true if entity_pid_set[child.persistent_id]

          inner = if child.is_a?(Sketchup::Group)
                    child.entities
                  elsif child.respond_to?(:definition)
                    child.definition.entities
                  end
          inner ? any_checked_descendant?(inner, entity_pid_set) : false
        end
      end

      # True when at least one direct entity inside the definition is checked.
      # Triggers case 7 (definition-level split required in SketchUp throwaway).
      def any_checked_in_def?(defn)
        defn.entities.any? { |e| BoundaryStore.checked?(e) == true }
      end

      # Assigns the correct policy case for a shared-definition entry.
      #
      # Priority order (mirrors policy.md guardrail ordering):
      #   7 — definition has checked sub-parts → split needed regardless of own state
      #   8 — exactly 1 out of N occurrences is checked → occurrence override
      #   6 — this occurrence is checked (confirmed shared SM_)
      #   5 — unchecked pass-through placement
      def assign_case_shared(is_checked, has_checked_def_child, checked_count, total_count)
        return 7 if has_checked_def_child
        return 8 if is_checked && checked_count == 1 && total_count > 1
        is_checked ? 6 : 5
      end

      # Stable merge key for shared definitions.
      # Format: "<def_name>__<sorted_child_paths>"
      # Identical across all instances with the same definition + checked sub-structure,
      # so two resolve() calls on the same model always produce the same key.
      def merge_key_for_shared(defn)
        checked_children = defn.entities.select { |e| BoundaryStore.checked?(e) == true }
        child_part = checked_children
          .map { |e| (BoundaryStore.get_path(e) || [e.persistent_id]).join('/') }
          .sort
          .join(',')
        "#{defn.name}__#{child_part}"
      end

      # Depth of a specific entity placement in the model hierarchy.
      # 0 = directly in model.entities; increments for each nested drawing context.
      # Walks up via parent Entities → ComponentDefinition → instances.first → …
      # Taking instances.first is correct for unique definitions; for shared defs
      # at mixed depths the caller should pass the specific instance directly.
      def compute_depth(entity)
        depth = 0
        ctx   = entity.respond_to?(:parent) ? entity.parent : nil

        loop do
          break if ctx.nil? || !ctx.respond_to?(:parent)

          owner = ctx.parent
          break if owner.nil? || owner.is_a?(Sketchup::Model)
          break unless owner.respond_to?(:instances)

          depth += 1
          inst = owner.instances.first
          break if inst.nil?

          ctx = inst.respond_to?(:parent) ? inst.parent : nil
        end

        depth
      end

    end
  end
end
