# Embedded FOC Model Style

Use these conventions when a user wants a readable Simulink implementation that can become embedded code. Preserve established project conventions when editing an existing model.

## Diagram Layout

Arrange signal flow left to right:

1. commands, sampled feedback, and type conversion;
2. controller boundary;
3. PWM/inverter interface;
4. simulation-only inverter, motor, load, and sensors;
5. scopes, logging, and assertions.

Inside the controller, make the execution hierarchy visible:

```text
FOC_Controller or FOC_Model
├─ CommandAndModeManager
├─ SpeedLoop                 (slow task)
├─ CurrentLoop               (fast task)
│  ├─ Clarke
│  ├─ Park
│  ├─ DqCurrentController
│  ├─ InversePark
│  └─ SVPWM
├─ StartupAndHandoff
├─ RotorFeedback             (sensor or estimator)
└─ ProtectionAndLimits
```

Use functional names. Preserve legacy names such as `currloop`, `speedloop`, `Clark`, `AntiPark`, or `tABC` when renaming would break generated interfaces or make history harder to follow.

## Block Choices

- Prefer standard `Sum`, `Gain`, `Product`, `Trigonometry`, `Saturation`, `PID Controller`, `Unit Delay`, `Rate Transition`, `Switch`, and `Merge` blocks for elementary control math.
- Use Stateflow for startup, mode, and fault state machines when transitions and temporal conditions need to be reviewed visually.
- Use MATLAB Function blocks for cohesive algorithms such as an estimator or sector calculation when a block-only implementation would obscure the logic. Keep types, sizes, persistent state, and code-generation support explicit.
- Keep Goto/From scope local when possible. Prefer buses or explicit ports across architectural boundaries.
- Use atomic subsystems or referenced models where a stable generated function boundary, reusable component, or scheduled partition is required. Atomicity is an architectural choice, not decoration.

## Controller Interfaces

Prefer grouped, stable interfaces over a growing list of untyped scalar ports. A typical controller contract contains:

- phase currents or reconstructed current samples;
- DC-bus voltage;
- enable, mode, reset, and fault inputs;
- speed or torque command;
- rotor position and speed from the selected feedback source;
- normalized duty cycles or timer compare commands;
- state, fault, and optional diagnostic outputs.

For an existing scalar-port model, preserve the port order and document it before refactoring. Record units and valid ranges on ports or bus elements.

## PI Controllers and Limits

- Use discrete PI control with an integration method chosen consistently with tuning and deployment. Forward Euler matches the analyzed teaching models; Tustin or backward Euler may be preferable when retuned and verified.
- Use anti-windup on current and speed controllers. Clamping is acceptable; back-calculation is useful when actuator saturation dynamics matter.
- Derive current-loop output limits from measured `v_dc` and the selected modulation convention. A fixed `24*0.9/sqrt(3)` limit is an example for a 24 V reference system, not a reusable universal constant.
- Limit the voltage vector consistently. Independent d/q saturation can distort vector direction; use circular/vector limiting when decoupling and field weakening require it.
- Limit the speed-loop `iq_ref` from motor, inverter, thermal, and operating-mode constraints. A reference value of ±3 A is not a default for another motor.
- Reset or track integrators during disable, alignment, faults, and mode transitions. Verify bumpless handoff.

For first-pass current-loop tuning, the analyzed material uses bandwidth-style estimates of the form `Kp = alpha * L` and `Ki = alpha * R`. Treat these as starting values and verify delay, PWM, sampling, cross-coupling, voltage limits, and discrete-time stability.

## Data and Parameters

- Use a `.sldd` or another version-controlled data definition for calibrations, buses, enums, and external interfaces.
- Prefer `Simulink.Parameter`, `Simulink.Signal`, `Simulink.Bus`, enums, and code mappings over exporting every intermediate signal.
- Use `single` for floating-point controller data on Cortex-M targets when supported. Use boolean and fixed-width integer types for modes, sectors, counters, and timer values.
- Make units part of the name, metadata, or interface definition: `speed_ref_rpm`, `omega_m_radps`, `theta_e_rad`, `vdc_V`, `iq_ref_A`.
- Preserve tunability intentionally. Inlined model parameters cannot be calibrated at run time unless given explicit storage or code mappings.
- Verify that a dictionary filename matches its on-disk capitalization exactly. Case-only mismatches may work on Windows and fail in CI or on another platform.

## Visual Review

- Keep subsystem boundaries aligned and avoid line crossings that hide feedback direction.
- Display meaningful signal names at transform, saturation, and rate boundaries.
- Annotate task rates and units at architectural boundaries.
- Put simulation sources and scopes in harness areas, not inside the controller component.
- Avoid cosmetic rewrites of a working legacy model unless they improve traceability, testability, or the generated interface.
