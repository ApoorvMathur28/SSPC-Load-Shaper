# SSPC Load Shaper — RTL Transient Load Shaper for CubeSat EPS

A **sink-side (load-side)** RTL (Verilog) **Solid-State Power Controller (SSPC)
load shaper** for a CubeSat Electrical Power System (EPS). It sits in series with a
single payload and soft-starts that payload's turn-on so its inrush current does not
brown out the shared DC bus. A finite-state machine monitors the bus voltage through
an ADC and applies an adaptive PWM soft-start to limit the average current the
payload draws when it switches on.

**Scope:** this is a *per-load* SSPC — it guards the bus against the inrush of the
one payload it is in series with. It is not a bus-wide brownout manager; the intended
architecture is one SSPC per load, each protecting its own turn-on. See
[Sink-side scope](#sink-side-scope-what-this-does-and-doesnt-do) below.

Verified in functional simulation against an unprotected baseline: under a
worst-case inrush scenario the unprotected bus browns out to **3.05 V** (below the
3.35 V threshold), while the shaped bus holds at **3.48 V** — a **~40% reduction in
bus voltage sag**.

---

## Problem

When a payload switches on, it draws a sudden burst of current. Pulled through the
battery's internal resistance and the harness, this inrush sags the shared bus
voltage. If the sag is deep enough, other loads — including the flight computer —
brown out and reset. Passively-balanced packs make this worse over mission life, as
cell mismatch and aging raise the effective series resistance and deepen every sag.

## Approach

A small FSM in RTL watches the bus and, instead of connecting the payload directly,
chops its power MOSFET with a ramped PWM duty cycle — a hardware soft-start. The
average inrush current rises gradually, so the bus never sags past its brown-out
threshold.

The controller has four states:

| State | Behavior |
|-------|----------|
| `OFF` | Payload disconnected. |
| `SHAPE` | Ramped PWM soft-start — duty cycle climbs from ~3% to 100%. Entered on every commanded turn-on and on any detected fast sag. |
| `MONITOR` | Full conduction; watches for critical voltage or a fast negative dV/dt. |
| `FAULT` | Bus went critical anyway — load shed and latched until the request clears. |

Two protection paths:
- **Proactive (primary)** — every commanded turn-on (`OFF → SHAPE`) soft-starts.
  A commanded turn-on is the most predictable inrush event and this is the SSPC's
  main job: prevent *its own* payload's inrush from sagging the bus.
- **Reactive (secondary, best-effort)** — a fast bus sag detected while conducting
  (`MONITOR → SHAPE`) re-shapes the load. Note that if the sag was caused by a
  *different* load on the shared bus, throttling this payload only partially relieves
  the bus — the architecturally correct fix is a dedicated SSPC on the offending
  load. This path is a local safety net, not a bus-wide manager.

## Design details

- **Sample-gated dV/dt** — the discrete voltage derivative is computed across
  consecutive *ADC samples* (gated by `adc_valid`), not clock cycles, since the ADC
  updates far slower than the 50 MHz clock.
- **Saturating duty arithmetic** — the duty-cycle ramp saturates at full scale
  instead of wrapping, avoiding a sudden collapse to near-zero conduction.
- **Hysteresis on recovery** — the `SHAPE → MONITOR` exit uses a recovery threshold
  ~100 mV above the fault threshold, so the FSM does not chatter at the fault line.
- **Fault telemetry** — a sticky `fault_latch` output records a brown-out event for
  flight-software readback, since the event itself is only tens of nanoseconds wide.
- **Safe default** — any illegal/undecoded state drives the switch open.

## Sink-side scope — what this does and doesn't do

This SSPC is **load-side**: it sits in series with one payload, senses the shared bus
voltage, and controls only that payload's MOSFET.

**What it does:** prevents the inrush of *its own* payload from browning out the bus,
by soft-starting that payload's turn-on (the proactive path). This is the correct and
complete job of a per-load SSPC.

**What it does not do:** it is not a whole-bus brownout controller. A single sink-side
SSPC can only throttle the one load it guards. If a *different* load causes a bus sag,
this SSPC's reactive response only partially helps (any current reduction relieves the
shared bus, but the right fix is an SSPC on the load actually causing the problem). In
a full EPS, each significant load gets its own SSPC; this module is one such instance.

Being explicit about this boundary is deliberate — the design solves the per-load
inrush problem cleanly rather than over-claiming bus-wide management.

## Files

| File | Description |
|------|-------------|
| `sspc_load_shaper.v` | The RTL module (parameterized FSM + PWM soft-start). |
| `tb_sspc.v` | Testbench with a discrete plant model; runs the same turn-on with and without shaping and prints the minimum bus voltage for each. |

## The plant model

The testbench models the battery + bus as a discrete integrator, updated each ADC
sample period:

```
i_load = load_on ? I_PEAK : 0
i_src  = (V_OC - v_bus) / R_PACK          // source current through pack resistance
q_cap  = q_cap + (i_src - i_load) * dt    // charge on the bus capacitor
v_bus  = q_cap / C_BUS                     // bus voltage
```

The shaped case drives the load through the PWM output, so `load_on` is chopped and
the *average* inrush is reduced; the unprotected case connects the load directly.

Worst-case parameters used for the headline result (aged pack, minimal bus cap):

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `V_OC` | 4.10 V | Pack open-circuit voltage |
| `R_PACK` | 0.30 Ω | Internal + harness resistance (aged) |
| `C_BUS` | 47 µF | Bus capacitance (deliberately small) |
| `I_PEAK` | 3.5 A | Payload steady current |

## Results

```
UNPROTECTED  min bus = 3.05 V     (brown-out: below 3.35 V threshold)
SHAPED       min bus = 3.48 V     (held above threshold)
```

```
sag_unprotected = 4.10 - 3.05 = 1.05 V
sag_shaped      = 4.10 - 3.48 = 0.62 V
reduction       = (1.05 - 0.62) / 1.05 ≈ 40%
```

The shaper does not eliminate sag — it keeps it within the safe margin. Under
gentler operating conditions the shaped bus holds even higher; the harsh plant above
is a stress case chosen to show the protection works where it matters.

### Waveform

![Payload turn-on, unprotected vs shaped. Left (bypass mode): the bus sags to 3.05 V, below the 3.35 V brown-out line. Right (shaped): the FSM soft-starts the load via PWM — payload_pwm chops the current — and the bus holds at 3.48 V, above the threshold. state_o walks OFF → SHAPE → MONITOR.]
<img width="1568" height="759" alt="image_2026-08-20_145646184" src="https://github.com/user-attachments/assets/816fc8d0-82ad-4d29-a065-cd23e381c0af" />

**How to read it:** the same payload turn-on is run twice. In the first run
(`bypass = 1`) the load connects directly and `v_bus_adc` plunges deep — this is the
unprotected brown-out. In the second run (`bypass = 0`) the shaper is active:
`payload_pwm` chops the load current (visible as the fast pulse train), the FSM ramps
the duty cycle up, and `v_bus_adc` dips far less before recovering. The captured
minimum for each run (`vmin`) is printed to the console. Some PWM ripple is visible on
the shaped bus during ramp-in — this is expected and stays well above the fault line.

## Reproducing

Requires Xilinx Vivado (tested on 2022.2) or any Verilog simulator (Icarus Verilog,
ModelSim).

**Vivado**
1. Create an RTL project (any part — this is simulation only).
2. Add `sspc_load_shaper.v` as a design source and `tb_sspc.v` as a simulation
   source; set `tb_sspc` as the simulation top.
3. Run Behavioral Simulation, then type `run all` in the Tcl Console.
4. The two `min bus` lines print in the Tcl Console.

**Icarus Verilog**
```bash
iverilog -o sim sspc_load_shaper.v tb_sspc.v
vvp sim
```

## Scope and honesty note

This is a functional (behavioral) simulation of the RTL against a discrete plant
model and an unprotected baseline. It is **not** synthesized to an FPGA, and the
"plant" is a lumped software model, not a SPICE circuit or measured hardware. The
~40% figure is a simulation result under the stated worst-case parameters.

## Possible extensions

- SPICE co-simulation with a real surge-stopper IC (e.g. LTC4364) as a commercial
  baseline.
- Triple-modular redundancy on the state register for single-event-upset tolerance.
- A watchdog timeout in `SHAPE` and an ADC plausibility (stuck-value) check.
