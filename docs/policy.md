# SKP-to-Max Policy

## Pipeline
SketchUp (boundary authoring) →
staging export (throwaway .skp + manifest.json) →
3ds Max (import .skp, attach per manifest) →
Datasmith → Unreal Engine

## 8-Case Attachment Table

| # | Node type | Checked | Has checked child | Result | Where |
|---|---|---|---|---|---|
| 1 | unique | ✓ | yes | A_ actor node, preserve hierarchy | structure |
| 2 | unique | ✓ | no | SM_ single mesh (all interior geo merged) | Max attach |
| 3 | unique | ✗ | – | sweep into nearest checked ancestor BODY | Max attach |
| 4 | unique top-level | ✗ | – | skip export + warn (no owner) | – |
| 5 | shared def (≥2 inst) | ✗ | no | SM_ 1 mesh × N placements — DO NOT sweep | pass-through |
| 6 | shared def | ✓ | no | same as #5, check = explicit confirm | pass-through |
| 7 | shared def | – | has checked sub-part | split at definition level: SM_<def>_<part> + SM_<def>_body, both instanced ×N | SKP restructure |
| 8 | occurrence override (explicit) | – | – | make-unique this occurrence only → apply #1–3 | SKP staging |

## 4 Guardrails (override everything)

1. shared instance NEVER swept into BODY — this overrides unchecked-sweep always
2. "same definition" = read from ComponentDefinition object, never inferred from checkbox or name similarity
3. definition split/restructure happens in SketchUp throwaway only — Max attaches unique geometry only, never touches shared
4. validate before every export: every persistent_id in manifest must resolve to a live entity

## manifest.json location
Always written alongside the exported .skp in the same folder.
`scene.skp` + `scene.manifest.json`

## What this repo is NOT
- No FBX carrier
- No geometry rebuild
- No OB_SOURCE copies
- No carrier_staging
- No fidelity_baseline
