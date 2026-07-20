# FOC Control Architecture and Build Sequence

## Select the Deliverable

Choose one of four model shapes before building:

| Deliverable | Includes | Excludes |
| --- | --- | --- |
| Algorithm unit | One transform, controller, modulator, state machine, or estimator plus a test harness | Complete plant and firmware interface |
| Closed-loop simulation | Controller, inverter, motor, load, sensors, stimuli, logging, assertions | Production-only drivers |
| Deployment controller | Sampled inputs, FOC logic, protection, duty/compare outputs | Plant, scopes, file I/O, desktop sources |
| Audit/migration | Existing behavior plus findings and focused corrections | Unrequested retuning or interface churn |

Use a separate harness or top-level simulation model around the deployment controller. This makes controller code buildable without dragging the motor plant into generated code.

## Construction Sequence

### 1. Coordinate transforms

Build and test Clarke, Park, and inverse Park independently.

- Fix the Clarke scaling convention and phase order.
- State the positive rotation direction.
- Define whether the angle is electrical radians, degrees, or per-unit.
- Verify Park followed by inverse Park reproduces the alpha-beta vector within numeric tolerance.
- Test balanced three-phase currents at multiple angles, including wrap boundaries.

### 2. Modulation and plant harness

Build inverse Park, alpha-beta to phase voltage conversion, SVPWM, inverter, PMSM, load, and feedback acquisition.

- Decide whether the output is normalized duty `[0,1]`, centered duty `[-1,1]`, or timer counts.
- Clamp duty explicitly and define behavior when `v_dc` is invalid.
- Test all sectors and sector boundaries.
- Keep inverter and motor blocks outside the controller boundary.

An open-loop V/f or rotating-voltage test is useful for validating phase order, angle direction, inverter polarity, and the plant before closing the current loop.

### 3. Fast dq current loop

Use this chain:

```text
ia, ib, ic -> Clarke -> Park -> id/iq errors -> dq PI
            -> voltage limit -> inverse Park -> SVPWM -> dutyABC
```

- Run from the ADC/PWM synchronized fast task.
- Begin with `id_ref = 0` for surface PMSM operation unless MTPA or field weakening is in scope.
- Apply current limits before the PI and voltage limits after it.
- Add anti-windup and explicit enable/reset behavior.
- Add decoupling/feed-forward only after the base loop is verified.

### 4. Startup and handoff

For a sensorless or uncertain initial angle, use explicit states such as:

```text
Disabled -> Align -> OpenLoopRamp -> Transition -> ClosedLoop
                   \-> Fault
```

Define entry actions, exit conditions, timeouts, current limits, angle source, speed source, and integrator behavior for every state. Blend angle or speed estimates during transition when an abrupt switch would cause torque disturbance.

A valid Hall system may enter closed loop at zero speed if sector decoding, direction, interpolation behavior, and startup torque have been verified. Do not add open-loop dragging solely because another estimator needs it.

### 5. Slow speed loop

The speed PI produces torque-producing current reference.

- Run slower than the current loop, normally at an integer decimation.
- Limit output by available current and operating mode.
- Reset or track its integrator when the current loop is unavailable.
- Filter measured speed only when the added phase delay is included in the design.

The analyzed teaching model uses 100 microseconds for the current loop and 1 millisecond for the speed loop. Some observer models use a 50 microsecond controller rate. Select actual rates from PWM, ADC, CPU budget, estimator needs, and loop bandwidth.

### 6. Rotor feedback component

Expose a common rotor-feedback interface:

```text
inputs: sampled currents, applied voltage or duty, vdc, sensor edges/data, enable
outputs: theta_e, omega_e or omega_m, valid, confidence/status
```

Implement one source behind it:

- encoder/resolver;
- Hall decoding and interpolation;
- Luenberger observer;
- sliding-mode observer;
- EKF;
- nonlinear flux observer.

Keep estimator state, sample time, startup validity, and failure behavior separate from the current controller.

## Multi-Rate Execution

Let `Ts_current` be the PWM/ADC synchronized base period and `Ts_speed = N * Ts_current`, where `N` is a positive integer. Estimator rate may equal the current rate or another documented integer partition.

Use one scheduling pattern consistently:

- hardware-triggered function-call subsystems;
- explicit periodic function-call generators in simulation with production mapping later;
- model-reference periodic rates with generated multi-rate entry points;
- a single base step plus deterministic decimation counters.

At every crossing, state whether data is held, delayed, buffered, or latched. Use Rate Transition blocks when the Simulink scheduler needs an explicit deterministic transfer. Account for the introduced delay in control design.

## Extension Order

Add advanced features only after the basic loop passes tests:

1. dq decoupling and voltage feed-forward;
2. field weakening or MTPA;
3. current reconstruction and sampling-window handling;
4. estimator confidence and fallback;
5. thermal/current derating;
6. fault diagnostics and limp modes;
7. fixed-point optimization or hardware-specific acceleration.
