# Hardware Commissioning Safety Gate

This is a conservative engineering gate for first power-on and controller commissioning. It does not replace the inverter, motor, MCU, laboratory, or organization-specific safety procedure.

Do not energize the power stage until every required item has an owner and recorded evidence.

## Before power

- Use an isolated, current-limited DC supply and begin at a reduced bus voltage appropriate for the hardware.
- Keep gate drive disabled by default during reset, boot, debugger halt, watchdog timeout, and loss of control power.
- Provide an independent hardware overcurrent trip that does not depend on the control task or generated software.
- Verify emergency stop, watchdog, contactor or supply disconnect, and the safe PWM shutdown path.
- Verify gate polarity, complementary outputs, dead time, minimum pulse behavior, shoot-through prevention, and driver fault feedback with the power stage de-energized.
- Confirm motor phase order, current-sensor polarity, ADC channel mapping, encoder/Hall order, electrical angle direction, pole pairs, and zero offset.
- Calibrate current-sensor offsets and plausibility thresholds before enabling closed-loop current control.
- Set conservative current, voltage, speed, acceleration, temperature, and duty-cycle limits.
- Ensure the model's fault state disables PWM and requires a deliberate, safe reset sequence.

## First rotation

1. Test PWM and ADC timing without energizing the motor.
2. Validate current readings with zero current and a known safe stimulus.
3. Use low bus voltage, current limiting, no load, and a mechanically safe setup.
4. Verify phase order and rotor angle direction with a small alignment or open-loop command.
5. Close the current loop before enabling the speed loop. Keep reference and voltage limits conservative.
6. Verify every stop and fault path, including sensor invalidity, overcurrent, watchdog, command loss, and debugger interruption.
7. Increase voltage, current, speed, and load in recorded stages only after waveform, temperature, and timing evidence is acceptable.

## Required evidence

- oscilloscope or logic-analyzer capture of gate timing and dead time;
- ADC sampling position relative to PWM and switching edges;
- measured current-offset and sensor-polarity results;
- fault injection showing safe gate disable;
- target task execution time and scheduling margin;
- temperature and bus/current limits used for each commissioning stage;
- person responsible for emergency shutdown.

If any item is unknown, treat hardware commissioning as blocked rather than assuming a safe default.
