# Embedded Code-Generation Contract

## Controller Boundary

Choose and document the generated component boundary, commonly `FOC_Controller` or an existing `FOC_Model`.

Allowed inside:

- sampled input conditioning and plausibility checks;
- mode, startup, protection, and reset logic;
- speed/current controllers and coordinate transforms;
- SVPWM and optional timer-command scaling;
- Hall processing or sensorless estimator when it belongs to the same scheduled component;
- diagnostics needed by firmware.

Keep outside:

- PMSM and inverter plant models;
- Signal Builder/Editor, desktop sources, dashboard blocks, scopes, and To Workspace logging;
- test-only fault injection and assertions that are not intended for production;
- host file I/O or unsupported visualization.

## Interface Definition

For each root input/output or bus element, record:

- name and physical meaning;
- unit and reference frame;
- data type and dimensions;
- normal and absolute range;
- sample time and owner;
- initialization/default value;
- invalid-data and reset behavior.

Recommended logical groups:

```text
FocCommand: enable, reset, mode, speed/torque/id/iq references
FocFeedback: ia, ib, ic, vdc, theta, speed, validity/status
FocOutput: dutyA, dutyB, dutyC, state, faults, diagnostics
```

Scalar legacy interfaces are acceptable when firmware already depends on their generated signature. Freeze and test the port order before changing it.

## Baseline Configuration

Use project constraints when supplied. Otherwise start from this deployment-oriented baseline:

| Setting | Preferred value | Reason |
| --- | --- | --- |
| Solver type | Fixed-step | deterministic scheduling |
| Solver | Discrete/no continuous states | controller implementation |
| Fixed step | explicit `Ts_current` | matches PWM/ADC task |
| System target | `ert.tlc` | embedded component code |
| Language | C99 | portable embedded C |
| Production hardware | actual ARM Cortex-M target | correct integer/word assumptions |
| Code-only build | on when integrating elsewhere | no host executable required |
| Code report | on | interface and traceability review |
| Non-finite support | off unless required | smaller deterministic implementation |
| Parameter behavior | deliberate, not accidental | balance optimization and calibration |

The analyzed models use ERT, C99, ARM-compatible hardware, generated-code reports, and often inlined parameters. They also mix `SupportNonFinite` settings. For new production models, choose these values explicitly and justify exceptions.

## Data Ownership and Calibration

- Prefer model code mappings and data dictionaries for stable definitions.
- Use exported globals only for firmware-visible symbols that genuinely require global linkage.
- Use tunable parameter storage for calibrations; inlined constants are appropriate for compile-time invariants.
- Avoid exporting transform intermediates merely for plotting. Use signal logging in the simulation harness and optional test points for debug builds.
- Keep dictionary and model filenames case-correct and relocatable. Resolve references from the project, not a developer-specific absolute path.

## Scheduling Contract

Document a table like this for every generated entry point:

| Entry point | Trigger | Period | Reads | Writes | Deadline |
| --- | --- | --- | --- | --- | --- |
| current step | PWM update or ADC end-of-conversion | `Ts_current` | currents, vdc, angle, current ref | duty/compare | before next PWM latch |
| speed step | deterministic decimation/timer | `N*Ts_current` | speed command/feedback, status | iq reference | before next current use |
| background | main loop/RTOS | noncritical | calibration/telemetry | diagnostics | no fast-loop blocking |

If generated code exposes one base-rate step function, document the internal decimation. If it exposes multiple entry points, map each one to a firmware ISR or task and protect cross-rate data.

## Firmware Integration

1. Generate into a versioned build folder, not directly over hand-edited firmware.
2. Inspect generated headers and the report before copying or compiling anything.
3. Add generated source through the build system. Do not edit generated `.c` files manually.
4. Write a thin adapter that converts ADC/timer units to the model interface and maps duty outputs back to hardware.
5. Call the fast entry point only from the documented PWM/ADC timing event. Keep telemetry and blocking HAL calls out of it.
6. Initialize model state once, then define enable, disable, fault, and reset sequencing.
7. Measure worst-case execution time and stack on the actual target.
8. Compare logged target behavior against simulation or SIL/PIL vectors.

## Code Review Questions

- Is the generated function signature stable and understandable?
- Are all controller states initialized and reset intentionally?
- Are divisions, lookup ranges, and invalid sensors guarded?
- Are calibration symbols tunable as intended?
- Is the current-loop deadline met with margin?
- Are rate crossings deterministic and free of partial updates?
- Does duty limiting remain safe for every bus voltage and fault state?
- Can generated files be reproduced from the committed model and configuration?
