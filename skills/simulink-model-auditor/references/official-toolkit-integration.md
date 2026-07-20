# Official Toolkit Audit Integration

The audit has two evidence layers:

1. Official Simulink Skills/MCP establish topology, exact parameters, structural diagnostics, project health, simulation behavior, tests, and Model Advisor results.
2. Bundled MATLAB scripts create repeatable generic and FOC-specific readiness reports without saving the model.

## Routing

| Audit evidence | Official Skill/tool | Local evidence |
| --- | --- | --- |
| Hierarchy and interfaces | `model_overview`, `model_read` | block/subsystem counts and selected scope |
| Exact values | `model_query_params`, `model_resolve_params` | common model configuration snapshot |
| Connectivity and Stateflow lint | `model_check` | additional unconnected-port heuristic |
| Project and dependencies | `managing-simulink-projects` | dictionary, model-reference, and link resolution |
| Dynamic behavior | `simulating-simulink-models`, `SimulationInput` | compilation only; no behavior claims |
| Persistent behavior | `testing-simulink-models`, `model_test` | utility-script unit tests only |
| Standards | `checking-model-compliance`, Model Advisor helpers | no standards claim |
| FOC domain | model tools above plus `$embedded-foc-simulink-codegen` | `audit_embedded_foc_model` |

## Mandatory audit sequence

1. Identify exactly one model and audit scope. If several `.slx` files are plausible, ask which one.
2. Open project context first when available. Verify project paths and dependencies before treating missing referenced artifacts as model defects.
3. Run `model_overview`, then `model_read`. Do not infer block paths by concatenating displayed names.
4. Query only parameters not already supplied by `model_read`. Compile queries only for properties that require compilation.
5. Run `model_check` and preserve its issue IDs, severities, block IDs, and messages.
6. Run `audit_simulink_model` with the requested profile. For FOC, run the specialization afterward.
7. If the user names a standard, use `checking-model-compliance`. If more than 100 checks resolve, obtain confirmation as required by the official Skill.
8. Separate observed facts from inferences and unexecuted recommendations in the final report.

## Read-only boundary

Do not invoke `model_edit`, change configuration, save, justify Model Advisor findings, suppress warnings, or generate code during an audit. A request to fix findings begins a separate workflow and requires explicit permission. Route fixes through `building-simulink-models`; satisfy its `.satk` custom-library gate first, then re-run all affected checks.

## Profile semantics

- `simulation`: compilation/structure failures remain FAIL; production-only omissions usually WARN.
- `deployment`: missing explicit fixed step, production target settings, unresolved artifacts, non-discrete rates, or unsafe interface types fail closed.
- `READY`: all scripted checks passed. It does not mean compliant, functionally correct, safe, or deployable without the missing official/dynamic evidence.
- `REVIEW`: no scripted FAIL but one or more warnings need engineering judgment.
- `NOT_READY`: at least one scripted FAIL.

## Failure behavior

- MCP unavailable: record the attachment failure and use local MATLAB only for the script layer. Do not imply that topology or `model_check` evidence was collected.
- Model cannot compile: report the exact compilation error and stop compiled-property claims.
- Missing product/license: identify the skipped official gate and keep readiness unresolved.
- Model Advisor result: state pass/warning/failure counts; never state that the model “is compliant.”
- FOC heuristic uncertainty: mark WARN and request behavior evidence instead of inventing intent from block names.

Official projects:

- <https://github.com/simulink/simulink-agentic-toolkit>
- <https://github.com/matlab/matlab-agentic-toolkit>
- <https://github.com/matlab/matlab-mcp-core-server>
