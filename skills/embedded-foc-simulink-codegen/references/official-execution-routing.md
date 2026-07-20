# FOC Execution Routing

This Skill supplies FOC decisions. MathWorks' official tools supply model operations.

| Intent | Official route | FOC-specific addition |
| --- | --- | --- |
| Understand hierarchy | `model_overview`, `model_read` | locate controller, plant, startup, rotor feedback, and task boundaries |
| Query values | `model_query_params`, `model_resolve_params` | check units, angle convention, gains, limits, and dictionary ownership |
| Edit structure | `building-simulink-models` + `model_edit` | FOC construction order, stable boundary, interface and timing |
| Check structure | `model_read` + `model_check` | plant separation and generated-boundary rules |
| Project/dictionary | `managing-simulink-projects` | firmware-owned calibrations and path resolution |
| Simulate | `simulating-simulink-models` + `SimulationInput` | startup, reversal, load step, bus variation, and sensor faults |
| Behavior regression | `testing-simulink-models` + `model_test` | limits, anti-windup, handoff, reset, and fault invariants |
| Compliance | `checking-model-compliance` + Model Advisor | record evidence without claiming certification |
| Audit | `$simulink-model-auditor` | generic readiness plus FOC-specific rules |
| Build | `run_embedded_foc_codegen` then `slbuild` | explicit user consent and deployment audit gate |

## Structural edit gate

Before the first `model_edit`, read `.satk/reuse-libraries.json`, `.satk/block-policy.json`, and `.satk/library-kg/index.md` together. If the declaration is missing, follow the official `setup-custom-libraries` Skill. If `confirmedNone: true`, use the official exception and skip policy/KG checks.

Use `model_read` to obtain block IDs; do not construct paths from displayed names. Use one `model_edit` scope at a time with `layout_mode="full"` for an empty scope or `"incremental"` for an existing scope. Re-read and `model_check` after each scope. Do not use raw `add_block`/`add_line` to bypass the official tool.

## Safety boundaries

- Plant and desktop-only blocks stay outside `FOC_Controller`.
- No code generation without explicit consent and zero deployment-audit FAIL results.
- No hardware power-on without the companion safety checklist.
- If official MCP is unavailable, state what could not be verified; do not claim a complete model operation or audit.
