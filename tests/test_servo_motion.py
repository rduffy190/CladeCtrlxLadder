"""FB_ServoMotionSeq test plan (servo design §4), in the scan simulator.

    python3 tests/test_servo_motion.py build/MotionLad_Import.xml

The ML_ wrappers are replaced by a motion model with the same Execute handshake: a command is
issued on the first call with bExecute, finishes CMD_SCANS scans later, and is re-armed when
bExecute drops. Gear-in sets the slave's InSynchronization; the VM's InVelocity follows the
velocity command; a halt or abort of a slave ends its gearing.
"""
import sys
from simx import XSim, Stub, Report, set_machine_state

STATES = ["Off", "TurningOn", "Idle", "Starting", "Running", "Stopping", "Holding", "Hold",
          "UnHolding", "Aborting", "Aborted", "Resetting"]
S = {n: i for i, n in enumerate(STATES)}
SEQ = ["Idle", "Positioning", "GearingIn", "Synced", "VmRunning", "VmSpeedChange", "VmHalting",
       "Ungearing", "AbortVm", "AbortSlaves"]
AXES = {"AX1": 0, "AX2": 1, "VM": 2}
CONSTS = {f"GVL_Axes.{k}": v for k, v in AXES.items()}
CMD_SCANS = 5


class Cmd(Stub):
    """Execute/Done command: done CMD_SCANS scans after it is issued."""

    def __init__(self, axis, **extra):
        super().__init__(bDone=False, bError=False, **extra)
        self.axis, self.issued, self.count, self.issues, self.fail = axis, False, 0, 0, False

    def status(self, sim, field, value=None):
        key = f"astStatus[GVL_Axes.{self.axis}].{field}"
        if value is not None:
            sim.v[key] = value
        return sim.v[key]

    def step(self, pins, sim):
        if pins["bExecute"] and not self.issued:
            self.issued, self.count = True, 0
            self.issues += 1
            self.on_issue(pins, sim)
        elif not pins["bExecute"]:
            self.issued = False
        if self.issued:
            self.count += 1
            if self.count == CMD_SCANS:
                self.on_done(pins, sim)
        self.out["bDone"] = self.issued and self.count >= CMD_SCANS and not self.fail
        self.out["bError"] = self.issued and self.fail
        self.extra(pins, sim)

    def on_issue(self, pins, sim): pass
    def on_done(self, pins, sim): pass
    def extra(self, pins, sim): pass


class Gear(Cmd):
    def on_done(self, pins, sim):
        self.status(sim, "InSynchronization", True)


class Stop(Cmd):
    def on_done(self, pins, sim):
        self.status(sim, "InSynchronization", False)
        if self.axis == "VM":
            self.status(sim, "InVelocity", False)


class Vel(Cmd):
    def __init__(self):
        super().__init__("VM", bSetpointChanged=False)
        self.velocity = None

    def on_issue(self, pins, sim):
        self.velocity = pins["lrVelocity"]
        self.status(sim, "InVelocity", False)

    def on_done(self, pins, sim):
        self.status(sim, "InVelocity", True)

    def extra(self, pins, sim):
        self.out["bSetpointChanged"] = self.issued and abs(pins["lrVelocity"] - self.velocity) > pins["lrDeadband"]


def new():
    stubs = {"_fbAx1Pos": Cmd("AX1"), "_fbAx2Pos": Cmd("AX2"), "_fbVmPos": Cmd("VM"),
             "_fbAx1Gear": Gear("AX1"), "_fbAx2Gear": Gear("AX2"), "_fbVmVel": Vel(),
             "_fbVmHalt": Stop("VM"), "_fbAx1Halt": Stop("AX1"), "_fbAx2Halt": Stop("AX2"),
             "_fbVmAbort": Stop("VM"), "_fbAx1Abort": Stop("AX1"), "_fbAx2Abort": Stop("AX2"),
             "_fbStateReq": Stub()}
    s = XSim(sys.argv[1], "FB_ServoMotionSeq", stubs=stubs, consts=CONSTS)
    for k in AXES:
        for f in ["PowerOn", "HasError", "InSynchronization", "InVelocity"]:
            s.v[f"astStatus[GVL_Axes.{k}].{f}"] = f == "PowerOn"
        s.v[f"asAxisName[GVL_Axes.{k}]"] = k
    s.v.update(lrSpeedCmd=100.0, lrAx1Offset=30.0, lrAx2Offset=330.0)
    return s, stubs


def seq(s):
    n = s.v["_eSeqState"]
    return SEQ[n] if 0 <= n < len(SEQ) else n


def run(s, ms, state):
    """Run ms in a machine state. Returns the sequence states passed through."""
    set_machine_state(s, state)
    seen = [seq(s)]
    for _ in range(ms // s.dt):
        s.scan()
        if seq(s) != seen[-1]:
            seen.append(seq(s))
    return seen


def client(st):
    p = st["_fbStateReq"].pins
    return p["bDone"], p["bAbort"], p["uiAbortCode"]


def to_running(s):
    run(s, 50, "Idle"); run(s, 500, "Starting"); run(s, 200, "Running")


r = Report("FB_ServoMotionSeq")

# 1 Idle does nothing outside Starting
s, st = new()
seen = run(s, 200, "Idle")
r.check("01 Idle in machine Idle: no motion, done", seen == ["Idle"] and client(st)[0] and st["_fbAx1Pos"].issues == 0)

# 2 Starting: position, gear in, synced; done only in Synced
set_machine_state(s, "Starting"); s.scan()
r.check("02 Starting not done while positioning", not client(st)[0])
seen = run(s, 500, "Starting")
r.check("03 Starting -> Positioning -> GearingIn -> Synced, done",
        seen == ["Positioning", "GearingIn", "Synced"] and client(st)[0], seen)
r.check("04 positioning targets: Ax1 -> offset 1, Ax2 -> offset 2, VM -> 0",
        (st["_fbAx1Pos"].pins["lrPosition"], st["_fbAx2Pos"].pins["lrPosition"], st["_fbVmPos"].pins["lrPosition"]) == (30.0, 330.0, 0.0))
r.check("05 gear-in slave offsets and master", (st["_fbAx1Gear"].pins["lrSlaveOffset"], st["_fbAx2Gear"].pins["lrSlaveOffset"],
                                                st["_fbAx1Gear"].pins["sMasterName"]) == (30.0, 330.0, "VM"))

# 6 Running: VM velocity at the speed command
seen = run(s, 200, "Running")
r.check("06 Running -> VmRunning at lrSpeedCmd", seen == ["Synced", "VmRunning"] and st["_fbVmVel"].velocity == 100.0, seen)

# 7 speed change: one scan in VmSpeedChange, velocity re-issued with the new speed
issues = st["_fbVmVel"].issues
s.v["lrSpeedCmd"] = 150.0
seen = run(s, 100, "Running")
r.check("07 speed change -> VmSpeedChange (1 scan) -> VmRunning, re-issued at 150",
        seen == ["VmRunning", "VmSpeedChange", "VmRunning"] and st["_fbVmVel"].issues == issues + 1
        and st["_fbVmVel"].velocity == 150.0, seen)
s.v["lrSpeedCmd"] = 150.005
seen = run(s, 100, "Running")
r.check("08 change within the deadband: not re-issued", seen == ["VmRunning"] and st["_fbVmVel"].issues == issues + 1, seen)

# 9 Holding: VM halts, slaves stay geared, done in Synced
seen = run(s, 300, "Holding")
r.check("09 Holding -> VmHalting -> Synced, done, slaves still synced",
        seen == ["VmRunning", "VmHalting", "Synced"] and client(st)[0]
        and s.v["astStatus[GVL_Axes.AX1].InSynchronization"], seen)
seen = run(s, 100, "Hold")
r.check("10 Hold: stays Synced, done", seen == ["Synced"] and client(st)[0])

# 11 UnHolding: done only once the VM is at speed
set_machine_state(s, "UnHolding"); s.scan(); s.scan()
r.check("11 UnHolding: VmRunning but not at speed yet -> not done", seq(s) == "VmRunning" and not client(st)[0])
run(s, 200, "UnHolding")
r.check("12 UnHolding: VM at speed -> done", client(st)[0])

# 13 Stopping from Running: halt VM, ungear, Idle
run(s, 50, "Running")
set_machine_state(s, "Stopping"); s.scan()
r.check("13 Stopping not done until Idle", not client(st)[0])
seen = run(s, 300, "Stopping")
r.check("14 Stopping -> VmHalting -> Ungearing -> Idle, done",
        seen[-3:] == ["VmHalting", "Ungearing", "Idle"] and client(st)[0]
        and not s.v["astStatus[GVL_Axes.AX1].InSynchronization"], seen)

# 15 stop jump from Positioning
s, st = new()
run(s, 30, "Starting")
seen = run(s, 300, "Stopping")
r.check("15 stop during Positioning -> VmHalting -> Ungearing -> Idle",
        seen == ["Positioning", "VmHalting", "Ungearing", "Idle"], seen)

# 16 abort from GearingIn: VM first, then the slaves, at ABORT_DEC
s, st = new()
run(s, 80, "Starting")
seen = run(s, 300, "Aborting")
r.check("16 abort during GearingIn -> AbortVm -> AbortSlaves -> Idle, done",
        seen == ["GearingIn", "AbortVm", "AbortSlaves", "Idle"] and client(st)[0], seen)
r.check("17 abort deceleration used", st["_fbVmAbort"].pins["lrDeceleration"] == 1440.0
        and st["_fbAx1Abort"].pins["lrDeceleration"] == 1440.0)

# 18 abort from VmHalting (on the stop path)
s, st = new()
to_running(s)
run(s, 20, "Stopping")
seen = run(s, 300, "Aborting")
r.check("18 abort during VmHalting -> AbortVm", seen[:2] == ["VmHalting", "AbortVm"] and seen[-1] == "Idle", seen)

# 19 abort with the VM in error and the stop failing: never hangs
s, st = new()
to_running(s)
st["_fbVmAbort"].fail = st["_fbAx1Abort"].fail = True
s.v["astStatus[GVL_Axes.AX2].PowerOn"] = False
seen = run(s, 200, "Aborting")
r.check("19 abort with failing stops / unpowered axis still reaches Idle", seen[-1] == "Idle" and client(st)[0], seen)
r.check("20 no abort request raised in Aborting", not client(st)[1])

# 21 command error -> abort request with the axis code
s, st = new()
st["_fbAx2Pos"].fail = True
run(s, 50, "Starting")
r.check("21 Ax2 positioning fails -> abort 301", client(st)[1:] == (True, 301), client(st))
st["_fbVmPos"].fail = True
run(s, 20, "Starting")
r.check("22 Ax2 and VM fail -> Ax2's code first (axis order)", client(st)[1:] == (True, 301), client(st))

# 23 invalid state value -> AbortVm
s, st = new()
to_running(s)
s.v["_eSeqState"] = s.v["_eNextSeqState"] = 33
seen = run(s, 300, "Running")
r.check("23 invalid sequence state -> AbortVm -> AbortSlaves -> Idle", seen[1:] == ["AbortVm", "AbortSlaves", "Idle"], seen)

# 24 outputs are copies
r.check("24 eSeqState output follows the state", s.v["eSeqState"] == s.v["_eSeqState"])

sys.exit(r.done())
