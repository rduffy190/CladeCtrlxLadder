# Unit: Drive Hardware Station: Design

*2026-10-08 · Draft for review · Parent: [Central State Management](Central_State_Management_Design.md) · Related: [Servo Station](Unit_ServoStation_Design.md)*

## 1. Purpose and scope

The drive hardware station manages the **drive power supply**, the DC bus that feeds the servo drives. It's one block, **`FB_DriveSupplyMgr`**, with one state client (`FB_StateRequest`). It follows the machine state it's given as its `stMachineState` input (wired by the calling program to the broadcast `GVL_State.stMachineState`; central doc, open question 7).

**It owns:**
- switching the supply on, but only once every drive reports it's ready for power;
- switching the supply off, but only once no axis is under torque;
- detecting a supply that doesn't come on, drops out or faults, and requesting an abort for it;
- waiting in Resetting for supply and drive faults to clear. The reset itself is the drive reset of drive 0, which hosts the supply, issued by the servo station.

**It does not own:** axis power or torque. That belongs to the servo station's axis manager. The two units never talk to each other. This unit reads the drive status words, and the servo station reads its axes' ready-for-power feedback from the motion system. That's enough to order them correctly (§4).

As with the other unit docs, this one is library-agnostic. The supply command, supply feedback and drive status words are plain signals, mapped from whatever I/O the hardware provides.

## 2. Drive status word: bits 15/14 and bit 13

Every axis drive reports its readiness in bits 15 and 14 of its status word:

| Bit 15 | Bit 14 | Meaning | Used as |
|---|---|---|---|
| 0 | 0 | Not ready for power | Blocks power-on |
| 0 | 1 | Ready for power | **Ready for power** (bit 14 or bit 15 set) |
| 1 | 0 | Power section ready, torque-free | Ready for power, not under torque |
| 1 | 1 | Under torque | **Under torque** (bit 14 and bit 15 set) |

Two derived levels, taken across all axis drives:
- `bAllReadyForPower := every drive has (bit 14 OR bit 15)`
- `bAnyUnderTorque := any drive has (bit 14 AND bit 15)`

**Bit 13 is the fault bit.** It's checked on every axis drive's status word and on the **supply's own status word**:
- `bAnyDriveFault := any drive has bit 13`
- `bSupplyFault := supply status word bit 13`

## 3. Behaviour per machine state

| Machine state | Supply | Done when |
|---|---|---|
| **Off** | Off, once no axis is under torque | Supply off |
| **TurningOn** | On, once all drives are ready for power | Supply on |
| Idle, Starting, Running, Stopping, Holding, Hold, UnHolding | On | Immediately: nothing to do beyond staying on |
| **Aborting** | Stays on until **no axis is under torque**, then off | No axis under torque **and** supply off |
| **Aborted** | Off | Immediately |
| **Resetting** | Reset supply and drive faults, then on once all drives are ready for power | No faults **and** supply on |

### The supply command as one level rule

```
bWantOn     := NOT stMachineState.bOff AND NOT stMachineState.bAborted AND NOT stMachineState.bAborting;
_bSupplyCmd := (bWantOn AND (_bSupplyCmd OR bAllReadyForPower))    // switch on only when all are ready; stay on
               OR (_bSupplyCmd AND bAnyUnderTorque);                 // never switch off while any axis is under torque
```

- **Ready check, at switch-on only.** Once the supply is on, the drives move to "power section ready" or "under torque". Both still count as ready, and the supply holds itself on.
- **Torque check, at switch-off.** This applies to any switch-off, whether to Off or in Aborting. The supply goes off only after every axis is torque-free.
- `_bSupplyCmd` is internal. Reading its value from the previous scan is a self-hold, not a read of an output. The output `bSupplyOnCmd` is a copy.

## 4. Ordering with the servo station, via hardware status only

| Phase | Drive hardware station | Servo axis manager |
|---|---|---|
| TurningOn / Resetting | Waits until all drives are *ready for power*, then switches the supply on | Waits until each axis reports *ready for power* (motion feedback, which follows the DC bus for a real axis), then enables the axes |
| Aborting | Holds the supply on while any axis is *under torque*, then switches off | Stops the axes, then commands them **torque-free** once at rest, still in Aborting |
| Off | Switches off once no axis is under torque | Disables the axes |

The machine can only leave **Aborting** when both units are done: the axes are torque-free and the supply is off. **Aborted** is therefore reached with the bus already down.

## 5. Fault detection: abort requests

**Any fault aborts.** Outside Aborting, Aborted and Resetting (central doc §4), the block requests an abort (through its client) while any of these is TRUE:

| Abort code | Condition |
|---|---|
| `ABORT_SUPPLY_CTRL` | The supply didn't reach the commanded mode in time (or its controller rejected the command) |
| `ABORT_SUPPLY_FAULT` | The supply reports an internal error, read from its status word. **This also covers a supply that drops out after it was on.** |
| `ABORT_DRIVE_FAULT + i` | Drive *i* fault: drive *i* status word bit 13 |

**Only power-on aborts on time.** The supply controller supervises every mode change, on and off. An off change only happens in Off, where the manager ignores aborts, or in Aborting, where fault aborts aren't raised. So in practice only a supply that fails to come on causes an abort. Once the supply is up, a drop-out shows as a supply fault.

There's no local timeout for drives that never become ready for power. The supply simply isn't commanded, this client never reports done, and the manager's TurningOn or Resetting timeout aborts with this client recorded as not done.

## 6. Reset

**This block doesn't reset anything itself.** The supply is built into drive 0, which is Ax1's drive, so the **drive reset of drive 0** clears supply errors as well as drive errors. The servo station's axis manager resets both axes on entry to Resetting, whatever the fault was (servo doc §3). Any fault aborts, so Resetting always follows a fault, and the reset doesn't need to know which one.
- This block waits in Resetting. When the faults clear, the drives report ready for power and the supply rule (§3) brings the supply back to operation.
- If the supply controller itself is in error, its enable is held off while Resetting, which clears it.
- The block is done when there are no faults and the supply is in operation.
- If the reset doesn't clear things, the manager's Resetting timeout aborts again.

## 7. Interface

| Input | Meaning |
|---|---|
| `awDriveStatus` | Status words of the **drives in use** on this supply (array: drive 0 = Ax1, drive 1 = Ax2): bits 15/14 readiness, bit 13 fault. The spare drive 2 isn't included. |
| `wSupplyStatus` | Supply unit status word: operating mode and internal error |
| Client attachment | One `I_StateClient`, e.g. `GVL_State.aClients[CLIENT_DRIVE_HW]` |

| Output | Meaning |
|---|---|
| `wSupplyCtrl` | Supply unit control word (in/out): drives the supply to operation or mains off |
| `awDriveDcBusCtrl` | DC bus power control of each drive (in/out): "DC bus power" is set while the supply is in operation |
| Diagnostics | `bSupplyInOperation`, `bSupplyOff`, `bAllReadyForPower`, `bAnyUnderTorque`, `bAnyDriveFault`, `bSupplyFault`, the abort code raised |

**Constants:** `SUPPLY_MODE_TIMEOUT`, `ABORT_SUPPLY_CTRL`, `ABORT_SUPPLY_FAULT`, `ABORT_DRIVE_FAULT`.

## 8. Internal structure

As with the servo axis manager, there's no internal state machine. Everything is a level function of the machine state and the hardware status:
1. read the status: decode each drive's status word with a sub-function (ready for power, under torque, fault), and read the supply's mode and error from its controller;
2. fault conditions → abort request and code;
3. echo and done from the machine state (§3 table);
4. command levels: `_bSupplyCmd` → supply target mode (operation / mains off), the supply controller's enable, and DC bus power to each drive;
5. call the sub-FBs (supply controller, client wrapper), then copy the outputs last.

## 9. Decisions and assumptions

**Decided:**
1. Power-on is allowed only when every drive is **ready for power** (status bit 14 or 15).
2. A supply that doesn't power on means **abort**. **Only power-on aborts on time** (see §5). A drop-out after power-on is caught as a supply fault.
3. In Aborting, the supply goes off only after **no axis is under torque** (bits 14 and 15 not both set), and that happens **within Aborting**. The servo station makes its axes torque-free at the end of Aborting.
4. Resetting **brings the supply back on** once the faults are cleared. **The reset is the drive reset of drive 0** (the supply is built into it), issued by the servo axis manager. This block has no reset output.
5. **A supply or drive fault means abort**: a supply internal error, or bit 13 of any drive status word.
6. **The supply is off in Off and Aborted, and on in every other state**, including Idle (confirmed).
7. **There are 3 drives and 1 supply.** Drive 0 is Ax1 and hosts the supply, and drive 1 is Ax2. These two get DC bus power while the supply is in operation. **Drive 2 is a spare and doesn't count**: it isn't part of readiness, torque or fault checks.

**Assumed (please confirm):**
1. ~~One supply feeds all the axis drives~~ **Confirmed:** one supply feeds all 3 drives. The VM has no drive.
2. ~~Drop-out covered by the on-feedback timeout~~ **Decided otherwise:** a drop-out is caught by the supply fault (bit 13). Only power-on is timed.
