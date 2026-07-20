# Reference Findings and Design Decisions

This Skill was rebuilt from an engineering review of user-provided local material:

- a 276-page STM32G4 Simulink FOC development manual, release V13.1;
- a local model corpus covering Clarke/Park, SVPWM/V-f, dq current loop, startup state logic, speed loop, Hall feedback, and Luenberger/SMO/EKF observer variants;
- the earlier `speedloop.slx`-based Skill.

The source PDF, screenshots, and model files are not distributed here. This document records generalized findings in original wording.

## Repeated Reference Pattern

The material builds the controller progressively:

1. validate Clarke;
2. add Park and inverse Park;
3. build SVPWM and test with an inverter/PMSM harness;
4. close the dq current loop;
5. add alignment/open-loop startup and state-based handoff;
6. add the speed loop;
7. replace or augment rotor feedback with Hall or a sensorless observer;
8. generate ERT code and integrate the controller entry point with embedded firmware.

Common model settings include fixed-step execution, `ert.tlc`, code-only generation, report generation, C99, ARM-compatible production hardware, data dictionaries, and mostly single-precision controller data.

## Timing Findings

- The teaching speed-loop model uses a 100 microsecond current-loop period and a 1 millisecond speed-loop period.
- Several observer-oriented models use a 50 microsecond controller subsystem sample time.
- Function-call generators, atomic subsystems, and Rate Transition blocks are used to represent execution boundaries.

Decision: the Skill does not universalize either numeric period. It derives `Ts_current` from PWM/ADC timing and requires all slow periods to be documented integer multiples.

## Control Findings

- The dq current loop follows Clarke -> Park -> PI -> inverse Park -> SVPWM.
- The teaching material uses bandwidth-style starting gains proportional to motor inductance and resistance.
- Speed PI output acts as q-axis current reference and is limited.
- Startup logic includes rotor alignment, an open-loop angle/speed ramp, and transition to speed closed loop.
- A Hall-based model can use a simpler zero-speed closed-loop path than sensorless startup.

Decision: retain this recognizable architecture, but make saturation, bus-voltage dependency, angle convention, reset, validity, and handoff explicit rather than copying reference constants.

## Code-Generation Findings

- The control subsystem is separated from the simulation plant and configured for ERT code generation.
- Generated model source/header files are integrated into an MCU project and the generated step function is called from the control timing path.
- Data dictionaries include signals, gains, motor parameters, sample times, and timer-related values.

Decision: formalize the controller interface and scheduler contract, prefer a thin firmware adapter, prohibit hand edits to generated code, and add build/SIL/PIL/target evidence gates.

## Issues Found During Corpus Audit

- Atomicity varies across tutorial and later observer models; not every `FOC_Model` is atomic.
- Some models rely on automatic fixed-step solver selection even though a numeric fixed step is present.
- An observer-oriented model declares a 50 microsecond controller subsystem while its model fixed step is 100 microseconds; this must be reconciled before deployment.
- `SupportNonFinite` is not consistent across variants.
- Many internal signals are exported globally for teaching/observation convenience.
- One Park model references a dictionary using capitalization that differs from the on-disk filename.
- Fixed voltage and current limits are tied to the example hardware.

Decision: turn these into audit checks, not inherited defaults. The improved Skill distinguishes pedagogical observability from production interfaces and checks portability, explicit timing, non-finite behavior, symbol visibility, and hardware-derived limits.

## Compatibility

Legacy models may retain `FOC_Model`, `currloop`, `speedloop`, `Clark`, `AntiPark`, and `tABC` names. New designs may use `FOC_Controller`, `CurrentLoop`, `SpeedLoop`, `Clarke`, `InversePark`, and `DutyABC`. Preserve an existing generated interface unless a migration is requested and tested.
