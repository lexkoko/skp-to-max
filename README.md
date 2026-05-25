# skp-to-max

`skp-to-max` is a pipeline bridge that lets SketchUp act as the boundary-authoring and instancing authority for scenes that ultimately land in Unreal Engine. Instead of rebuilding geometry in a carrier file, SketchUp exports real geometry — a throwaway staged `.skp` and an accompanying `manifest.json` — and 3ds Max reads both to attach meshes exactly as the manifest directs. No FBX carrier, no geometry reconstruction, no duplicate data.

## Pipeline Overview

1. **SketchUp** — artist authors component boundaries, marks checked/unchecked nodes, and triggers a staging export.
2. **Staging export** — produces `scene.skp` (real geometry, throwaway) + `scene.manifest.json` (attachment instructions keyed by `persistent_id`) in the same folder.
3. **3ds Max** — imports `scene.skp`, reads `scene.manifest.json`, and runs attach operations: merges unchecked geometry into checked-ancestor BODY meshes, preserves hierarchy for actor nodes, and passes shared-definition instances through as-is (×N placements, no sweep).
4. **Datasmith → Unreal Engine** — the cleaned Max scene exports via Datasmith for final assembly in UE.

## Status

Early setup phase. Folder structure and policy spec are in place; Ruby (SketchUp) and MaxScript (3ds Max) implementation begins with Issue 1A (`boundary_store`). See [docs/policy.md](docs/policy.md) for the 8-case attachment table and 4 guardrails that govern all code in this repo.
