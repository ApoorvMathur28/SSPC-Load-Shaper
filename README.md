# SSPC Load Shaper - RTL Design + SystemVerilog Verification

A **sink-side (load-side) Solid-State Power Controller (SSPC) load shaper** for a
CubeSat Electrical Power System (EPS), written in Verilog, with a class-based
SystemVerilog verification environment and a Perl regression/triage script.

The design sits in series with a single payload and soft-starts that payload's
turn-on so its inrush current does not brown out the shared DC bus. A finite-state
machine monitors the bus voltage through an ADC and applies an adaptive PWM
soft-start to limit the average current the payload draws when it switches on.

**Headline results (functional simulation):**
- Under a worst-case inrush, the unprotected bus sags to **3.05 V** (below the
  3.35 V brown-out line); the shaped bus holds at **3.48 V** — a **~40% reduction
  in bus voltage sag**.
- A constrained-random SystemVerilog testbench runs 20 randomized scenarios per
  regression, reaches **91.7% functional coverage**, and locates the **~2.5 A
  inrush limit** beyond which the shaper can no longer hold the bus above threshold.
- A Perl script parses the simulation log and reports pass/fail and coverage,
  returning a non-zero exit code on any failure.

---

## Repository layout

```
rtl/
  sspc_load_shaper.v       # the DUT: FSM + PWM soft-start
tb/
  tb_sspc.v                # plant-model testbench (shaped vs unprotected, prints min bus)
verif/
  sspc_if.sv               # interface + clocking block
  sspc_txn.sv              # randomized transaction (constrained-random)
  sspc_driver.sv           # drives the DUT + runs the bus plant model
  sspc_scoreboard.sv       # self-checking pass/fail + feeds coverage
  sspc_coverage.sv         # functional coverage (covergroups + cross)
  tb_top.sv                # top: wires DUT to interface, runs 20 randomized txns
scripts/
  triage.pl                # parses a sim log, reports pass/fail + coverage
docs/
  waveform.png             # bus voltage: unprotected sag vs shaped soft-start
```

(You can keep everything flat in one folder if you prefer — the folder split above
is just tidier.)

---

## The design

### Problem

When a payload switches on it draws a burst of inrush current. Pulled through the
battery's internal resistance and the harness, this sags the shared bus voltage. If
the sag is deep enough, other loads — including the flight computer — brown out and
reset. Aging, passively-balanced packs raise the effective series resistance and
deepen every sag over mission life.

### Approach

Instead of connecting the payload directly, the FSM chops its power MOSFET with a
ramped PWM duty cycle — a hardware soft-start. The average inrush current rises
gradually, so the bus never sags past its brown-out threshold.

Four states:

| State | Behavior |
|-------|----------|
| `OFF` | Payload disconnected. |
| `SHAPE` | Ramped PWM soft-start — duty climbs from ~3% toward 100%. Entered on every commanded turn-on and on any detected fast sag. |
| `MONITOR` | Full conduction; watches for critical voltage or a fast negative dV/dt. |
| `FAULT` | Bus went critical anyway — load shed and latched until the request clears. |

Two protection paths:
- **Proactive (primary):** every commanded turn-on (`OFF -> SHAPE`) soft-starts.
- **Reactive (secondary):** a fast sag detected while conducting (`MONITOR -> SHAPE`)
  re-shapes the load.

### Design details worth noting

- **Sample-gated dV/dt** — the voltage derivative is computed across consecutive ADC
  *samples* (gated by `adc_valid`), not clock cycles, since the ADC updates far
  slower than the 50 MHz clock.
- **Saturating duty arithmetic** — the ramp saturates at full scale instead of
  wrapping.
- **Hysteresis on recovery** — the `SHAPE -> MONITOR` exit uses a recovery threshold
  ~100 mV above the fault threshold, so the FSM does not chatter at the fault line.
- **Fault telemetry** — a sticky `fault_latch` records a brown-out event for
  flight-software readback.

### Sink-side scope

This is a **per-load** SSPC: it protects the bus against the inrush of the one
payload it is in series with. It is **not** a bus-wide brownout manager — a single
sink-side SSPC can only throttle its own load. In a full EPS, each significant load
gets its own SSPC. Being explicit about this boundary is deliberate.

---

## Verification

The verification environment is a **class-based SystemVerilog testbench** built from
the components UVM formalizes (interface, transaction, driver, scoreboard, coverage),
written in plain SystemVerilog rather than the UVM library.

- **Transaction (`sspc_txn.sv`)** — one stimulus item with `rand` fields (inrush
  current, delay, shaper-on) and constraints keeping them in a sensible range.
- **Driver (`sspc_driver.sv`)** — takes transactions, drives the DUT pins through the
  interface, and runs the discrete bus plant model alongside.
- **Scoreboard (`sspc_scoreboard.sv`)** — self-checking: compares the achieved
  minimum bus voltage against the spec rule (shaped bus must stay above 3.35 V) and
  prints PASS/FAIL.
- **Coverage (`sspc_coverage.sv`)** — covergroups record which inrush ranges, paths,
  and margin bands were actually exercised, plus a cross of inrush x shaper.

### The plant model

The testbench models the battery + bus as a discrete integrator, updated each ADC
sample:

```
i_load = load_on ? I_PEAK : 0
i_src  = (V_OC - v_bus) / R_PACK
q_cap  = q_cap + (i_src - i_load) * dt
v_bus  = q_cap / C_BUS
```

The shaped case drives the load through the PWM output (so the average inrush is
reduced); the unprotected case connects the load directly.

Worst-case plant parameters for the headline result:

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `V_OC` | 4.10 V | Pack open-circuit voltage |
| `R_PACK` | 0.30 ohm | Internal + harness resistance (aged) |
| `C_BUS` | 47 uF | Bus capacitance (deliberately small) |
| `I_PEAK` | up to 3.5 A | Payload inrush |

### Results

```
==== SCOREBOARD: 19 passed, 0 failed ====
==== COVERAGE: 91.7% ====
```

Constrained-random stimulus over the rated range passes cleanly. When the inrush
range is widened past ~2.5 A, the scoreboard automatically catches the boundary where
the shaper can no longer hold the bus above 3.35 V — a real, tool-found operating
limit rather than a hand-picked test.

### Waveform

![Payload turn-on, unprotected vs shaped. Left: the bus sags to 3.05 V, below the 3.35 V brown-out line. Right: the FSM soft-starts the load via PWM and the bus holds at 3.48 V.]
<img width="1568" height="759" alt="image_2026-08-20_145646184" src="https://github.com/user-attachments/assets/816fc8d0-82ad-4d29-a065-cd23e381c0af" />

---

## Automation

`scripts/triage.pl` parses a simulation log and reports results:

```
=======================================================
 SSPC Verification - Triage Report
=======================================================
 Tests passed : 19
 Tests failed : 0
 Coverage     : 91.7%
 All tests passed.
=======================================================
```

It reads the log byte-safe (handling Windows UTF-16/BOM logs), extracts the pass/fail
counts and coverage percentage via regex, lists any failing cases, and exits non-zero
if anything failed — so it can gate a CI run.

---

## Reproducing

Requires Xilinx Vivado (tested on 2022.2). Perl (any recent version) for the triage
script.

**RTL + plant testbench (the ~40% result):**
```
xvlog rtl/sspc_load_shaper.v tb/tb_sspc.v
xelab tb_sspc -s sspc_sim -debug typical
xsim sspc_sim -runall
```

**SystemVerilog verification (coverage + scoreboard):**
```
xvlog rtl/sspc_load_shaper.v
xvlog -sv verif/sspc_if.sv verif/sspc_txn.sv verif/sspc_coverage.sv \
         verif/sspc_driver.sv verif/sspc_scoreboard.sv verif/tb_top.sv
xelab tb_top -s sv_sim -debug typical
xsim sv_sim -runall > sim_output.log
```

**Triage:**
```
perl scripts/triage.pl sim_output.log
```

(If your files are all in one folder, drop the `rtl/`, `tb/`, `verif/` prefixes.)

---

## Scope and honesty

This is functional (behavioral) simulation of the RTL against a discrete plant model
and an unprotected baseline. It is **not** synthesized to an FPGA, the plant is a
lumped software model (not SPICE or measured hardware), and the verification is
class-based SystemVerilog, **not** the UVM library. All figures are simulation results
under the stated parameters.

## Possible extensions

- Port the testbench to the UVM library (sequencer, agent, factory, phases).
- SPICE co-simulation with a commercial surge-stopper (e.g. LTC4364) as a baseline.
- Triple-modular redundancy on the state register for single-event-upset tolerance.
- A watchdog timeout in `SHAPE` and an ADC plausibility (stuck-value) check.
