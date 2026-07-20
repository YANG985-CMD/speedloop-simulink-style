---
name: simulink-model-auditor
description: Audit any Simulink model or subsystem without changing it. Use for solver and sample-time review, compiled data types, structural risks, model references, library links, dictionaries, code-generation readiness, Model Advisor planning, or FOC-specific checks. Combines generic checks with MathWorks official Simulink Skills and MATLAB MCP evidence.
---

# Simulink Model Auditor

Use this Skill for read-only, evidence-based review of arbitrary Simulink models. It is domain-neutral by default; add the FOC specialization only when the model is a PMSM/BLDC FOC design. It does not silently edit or save models.

## Official inspection route

Read `references/official-toolkit-integration.md` before auditing.

1. Use `model_overview` to map hierarchy and interfaces, then `model_read` for the target scope.
2. Use `model_query_params` for exact configuration, sample-time, signal, and code-generation parameters. Use `model_resolve_params` for workspace/dictionary references.
3. Use `model_check` for unconnected ports, dangling lines, and Stateflow lint. Record its result separately from the MATLAB audit script.
4. Use `managing-simulink-projects` for project path, referenced models, dictionaries, and dependency health.
5. Use `checking-model-compliance` for Model Advisor standards. Report findings, never declare legal/certification compliance.
6. Use `simulating-simulink-models` with `SimulationInput` when the user asks for dynamic evidence.
7. Use `testing-simulink-models` and `model_test` for persistent model behavior tests. Use `matlab-testing`/`run_matlab_test_file` only for this Skill's utility scripts.

The MATLAB scripts provide repeatable local evidence; the official MCP tools provide topology, structural diagnostics, and exact tool provenance. Neither layer substitutes for the other.

For a disposable demonstration model, run `create_simulink_audit_example`. It creates a small valid or intentionally unsafe fixture; never treat it as a controller design or use it to bypass official `model_edit` on user models.

## Choose the audit lane

- Any model: run `audit_simulink_model` with `Profile="simulation"` or `"deployment"`.
- FOC model: run the generic audit first, then `audit_embedded_foc_model` with the same profile and controller path.
- Compliance request: run the appropriate official Model Advisor workflow after structural checks; do not infer a standard from the model name.
- Fix request: stop the audit-only lane, get explicit permission, and hand the edit to `building-simulink-models` or the relevant execution Skill. Re-run both official and local audits afterward.

## Generic audit

```matlab
addpath(fullfile(AUDITOR_SKILL_DIR, 'scripts'));
report = audit_simulink_model('any_model.slx', ...
    'Profile', 'simulation', ...
    'OutputFile', 'artifacts/simulink-audit.json');
```

Deployment profile is fail-closed for missing production configuration, broken model references or library links, structural unconnected ports, non-discrete compiled rates, and unexpected `double` controller/interface data. A warning means review is still required; `READY` is not certification.

## FOC specialization

```matlab
report = audit_embedded_foc_model('motor_control.slx', ...
    'ControllerPath', 'motor_control/FOC_Controller', ...
    'Profile', 'deployment', ...
    'OutputFile', 'artifacts/foc-audit.json');
```

The specialization checks controller/plant separation, FOC boundary timing, Rate Transition settings, recognizable PI limits and anti-windup, compiled rates/types, data dictionary, ERT/C99/target settings, and production numeric options. It is an additional domain contract, not a replacement for the generic audit.

## Reporting rules

Always report:

- model path, scope, MATLAB release, profile, and whether compilation succeeded;
- official MCP calls actually run and any unavailable/licensing failures;
- PASS/WARN/FAIL counts with check IDs and evidence;
- assumptions and checks that are heuristic or require Model Advisor, simulation, SIL/PIL, target timing, or hardware evidence;
- whether the model was changed (this Skill should say “no model changes”).

Never call `slbuild` from an audit. Never claim “the model is compliant,” “safe,” or “ready for hardware” from these reports alone.
