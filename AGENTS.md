# Rules for AI Coding Agents

Read docs/policy.md before writing any code.

## Hard rules
- Never create FBX export logic from SketchUp geometry
- Never rebuild/reconstruct faces or edges — transfer real geometry only
- Never make-unique a shared component at occurrence level unless
  case #8 (occurrence-override) is explicitly requested
- Never sweep a shared-definition instance into a BODY group
- Every PR must be small enough to test in isolation
- Attach logic lives in 3dsmax/ only — SketchUp side outputs
  manifest.json and staged .skp, nothing more

## Reuse from outliner-bridge (rewrite clean, keep logic)
- boundary_store: attribute read/write/delete on entities
  using persistent_id_path as key
- staging-abort operation: begin/rescue/ensure pattern that
  rolls back model state if any step fails — no partial writes

## File ownership
- sketchup/ : Ruby only, no MaxScript
- 3dsmax/ : MaxScript only, no Ruby
- docs/ : documentation only, never imported by code
- manifest.json : written by sketchup/, read by 3dsmax/

## Acceptance criteria format
Every PR must include in its description:
- What case(s) from policy.md this covers
- How to test manually in SketchUp or Max
- What should NOT change (regression guard)
