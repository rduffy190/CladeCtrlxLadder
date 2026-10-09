# Design docs

These design documents are the input for implementation. They're library-agnostic on purpose: they say *what* each block commands, and the motion and I/O libraries are chosen when the code is written.

## Documents

| Doc | Covers | Status |
|---|---|---|
| [Central_State_Management_Design.md](Central_State_Management_Design.md) | `FB_StateManager`, the broadcast machine state (`ST_MachineState`), `I_StateClient` / `FB_StateClient` / `FB_StateRequest`, echo + done, abort jumps | No open questions. 4 assumptions to confirm (§8). |
| [Unit_ServoStation_Design.md](Unit_ServoStation_Design.md) | `FB_ServoAxisMgr` (power, faults, reset, torque-free at end of Aborting), `FB_ServoMotionSeq` (position, gear-in, VM speed, hold, stop, abort) | No open questions. 4 assumptions to confirm (§7). |
| [Unit_DriveHardwareStation_Design.md](Unit_DriveHardwareStation_Design.md) | `FB_DriveSupplyMgr`: DC bus supply on/off from drive status bits 15/14, bit-13 fault aborts, reset | Complete |

## Implementation order

1. **Central state management:** `E_MachineState`, `ST_MachineState`, `I_StateClient`, `FB_StateClient`, `FB_StateRequest`, `FB_StateManager` and `GVL_State`. Everything else depends on these.
2. **Drive hardware station:** `FB_DriveSupplyMgr`. It has no motion and relies only on status words, so it's the simplest unit to bring up first.
3. **Servo station:** `FB_ServoAxisMgr`, then `FB_ServoMotionSeq`.
4. **Wiring:** a program that calls the manager and the units, assigns client indexes (`CLIENT_*` constants) and maps the hardware I/O (status words, supply signals, axis references).

## Rules every implementation follows

These come from the house style, which is captured in the `codesys-st` skill.

- **Sequences use four sections:** jumps → transitions (`CASE`, transitions only) → on change (`IF _eState <> _eLastState`: common actions, then entry actions) → cyclic (sub-FB calls, then all outputs last: command values as expressions of the state and copies of internal values).
- **No rising edges.** Commands are levels. A terminal state holds until its command is removed.
- **A POU never reads its own outputs.** The logic works on internal `_` variables, and the outputs are copies written at the end.
- **No first-scan logic.** Every state machine starts in its default (Off/Idle) state, which does nothing.
- **Enums vs constants:** an enum when the state is an output, `VAR CONSTANT` steps when it's internal. Implicit numbering, no gaps.
- **Any fault aborts.** Fault info is kept from the first cause and cleared on entering Idle.
- **Units never talk to each other.** They follow the broadcast state, report through their client, and order themselves by hardware status (e.g. drive status words).
- **No global data in an FB.** An FB never reads or writes a global variable. Global constants are allowed. The machine state reaches each unit through its `stMachineState` input (`ST_MachineState`: the enum plus one BOOL per state), wired by the calling program (central doc, open question 7), so another layer of state management can be added later without changing the units.

## Still to decide before or while coding

- **Central doc §8 assumptions 1–4** and **servo doc §7 assumptions 1–4:** to be confirmed.
- **The motion library has been chosen for implementation.** See `../CLAUDE.md`. Look up how the gear-in slave offset and on-the-fly VM speed map onto it when coding the servo station.
