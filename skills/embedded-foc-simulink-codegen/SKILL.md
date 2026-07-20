---
name: embedded-foc-simulink-codegen
description: Build, revise, simulate, test, and prepare PMSM/BLDC field-oriented-control Simulink models for deterministic embedded C code generation. Use for Clarke/Park transforms, dq current and speed loops, SVPWM, startup and handoff, Hall/encoder/sensorless feedback, multirate execution, ERT, STM32, or ARM Cortex-M deployment. Pair with simulink-model-auditor for generic and FOC-specific audits.
---

# Embedded FOC Simulink Codegen

This is the execution Skill for FOC models. It owns FOC architecture, timing, interfaces, safety decisions, and the explicit build gate. It does not replace MathWorks' generic model-operation Skills or the companion `simulink-model-auditor` Skill.

## Route every model operation through official tools

Read `references/official-execution-routing.md` before touching a model.

1. Inspect with official `model_overview`, `model_read`, `model_query_params`, and `model_resolve_params`.
2. Before structural edits, load `building-simulink-models`; satisfy the `.satk/reuse-libraries.json`, block-policy, and library-KG gate. Use `model_edit` one scope at a time.
3. After each edit, run `model_read`; after each completed scope, run `model_check`. If an edit is partial, run both immediately.
4. Route project paths, referenced models, callbacks, and dictionaries through `managing-simulink-projects`.
5. Route simulation through `simulating-simulink-models` with `Simulink.SimulationInput` and `Simulink.SimulationOutput`.
6. Route persistent model behavior tests through `testing-simulink-models` and `model_test`. Use MATLAB unit tests only for repository utilities.
7. Route Model Advisor through `checking-model-compliance`. Never claim legal or certification compliance from a check result.
8. Before handoff, invoke `$simulink-model-auditor` for the generic audit and its FOC specialization. If the companion Skill is not installed, report that dependency instead of silently weakening the gate.

Do not bypass `model_edit` with `evaluate_matlab_code` plus `add_block`, `add_line`, or `set_param` for agent-driven structural edits.

## FOC execution workflow

1. Classify the request as algorithm unit, closed-loop simulation, deployment controller, or migration.
2. Inspect the existing model, project, dictionary, callbacks, referenced models, solver, rates, code mappings, and target settings. Preserve tuned gains and hardware timing without evidence for changing them.
3. Read only the needed references: `control-architecture.md`, `style-guide.md`, `embedded-codegen-contract.md`, `verification-checklist.md`, and `hardware-commissioning-safety.md`.
4. Build or revise in stages: Clarke/Park, modulation, current loop, startup/handoff, speed loop, then optional estimator. Verify every stage.
5. Keep one explicit generated boundary such as `FOC_Controller`. Keep inverter, motor, stimuli, scopes, and desktop logging outside it.
6. Derive the fast task from PWM/ADC timing. Make slower tasks integer multiples and define every crossing explicitly.
7. Run official structural checks, focused simulations, behavior tests, Model Advisor, generic audit, and FOC audit. Only then consider code generation.

## FOC contract

- Fast path: `abc current -> Clarke -> Park -> dq PI -> inverse Park -> SVPWM`.
- Limit `iq_ref` and the dq voltage vector. Provide anti-windup for every actuator or reference saturation.
- Define angle units, electrical/mechanical meaning, direction, zero position, pole-pair conversion, and wrap range.
- Model disabled, alignment, open-loop ramp, transition, closed-loop, fault, and reset behavior explicitly. Verify bumpless handoff.
- Hide Hall, encoder, SMO, Luenberger, EKF, or other estimator internals behind a stable rotor-feedback interface.
- Prefer inspectable blocks for transforms and PI. Use MATLAB Function or Stateflow for stateful logic only when code generation remains supported.

## Embedded contract

- Use fixed-step discrete execution and an explicit PWM/ADC-derived base period.
- Prefer ERT, the chosen C standard, and real ARM Cortex-M word assumptions when available.
- Use `single` deliberately; retain boolean, integer, fixed-point, or wider accumulator types where required.
- Keep calibrations and firmware interfaces in version-controlled data definitions. Document units, ranges, types, sample times, validity, reset behavior, and ownership.
- Inspect generated entry points, scheduling, parameter representation, memory, stack, traceability, and WCET.

## Explicit build gate

Never call `slbuild` just because the user requested a model change or audit. Ask for explicit authorization. Then run:

```matlab
addpath(fullfile(FOC_SKILL_DIR, 'scripts'));
addpath(fullfile(AUDITOR_SKILL_DIR, 'scripts'));
build = run_embedded_foc_codegen('motor_control.slx', ...
    'ControllerPath', 'motor_control/FOC_Controller', ...
    'ConfirmBuild', true);
```

The helper refuses to build unless `ConfirmBuild=true` and the auditor's deployment profile has zero FAIL results. A successful build is not proof of control correctness, target timing, or hardware safety.

Before energizing hardware, read `hardware-commissioning-safety.md` and stop if independent overcurrent protection, safe gate disable, emergency shutdown, current-limited power, sensor calibration, or dead-time evidence is missing.

## Completion evidence

Report the changed model/boundary, control mode, rotor feedback, fast/slow periods and trigger, interface units/types/limits, official tools and tests actually run, audit/Model Advisor results, build authorization, unresolved assumptions, and unavailable products.
