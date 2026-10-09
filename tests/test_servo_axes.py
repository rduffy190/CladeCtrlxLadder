"""FB_ServoAxisPower and FB_ServoAxisMgr test plan (servo design §3), in the scan simulator.

    python3 tests/test_servo_axes.py build/MotionLad_Import.xml

FB_ServoAxisPower is tested with its ML_ wrappers as stubs. FB_ServoAxisMgr is tested with
its three axis blocks as models: an axis powers up a few scans after power is wanted (if
ready for power), and its status is written to astStatus[...] the way the RT reader does.
"""
import sys
from simx import XSim, Stub, Report, set_machine_state

STATES = ["Off", "TurningOn", "Idle", "Starting", "Running", "Stopping", "Holding", "Hold",
          "UnHolding", "Aborting", "Aborted", "Resetting"]
S = {n: i for i, n in enumerate(STATES)}
AXES = {"AX1": 0, "AX2": 1, "VM": 2}
CONSTS = {f"GVL_Axes.{k}": v for k, v in AXES.items()}
FIELDS = ["DataValid", "PowerReady", "PowerOn", "HasError", "Standstill"]
r = Report("FB_ServoAxisPower / FB_ServoAxisMgr")

# ===================== FB_ServoAxisPower =====================


def axis_power(i=1):
    stubs = {"_fbPower": Stub(bError=False), "_fbReset": Stub(bDone=False, bError=False)}
    s = XSim(sys.argv[1], "FB_ServoAxisPower", stubs=stubs)
    s.v.update({f"stStatus.{f}": False for f in FIELDS})
    s.v.update({"stStatus.DataValid": True, "stStatus.Standstill": True, "iAxis": i})
    return s, stubs


s, st = axis_power()
s.v["bWantPower"] = True
s.run(50)
r.check("P01 wanted but not ready for power: not switched on", st["_fbPower"].pins["bSwitchOn"] is False)
s.v["stStatus.PowerReady"] = True
s.run(20)
r.check("P02 ready for power -> power command on", st["_fbPower"].pins["bSwitchOn"] is True)
s.v["stStatus.PowerOn"] = True
s.run(20)
r.check("P03 powered: no fault", not s.v["bFault"] and s.v["uiAbortCode"] == 0)
s.v["stStatus.PowerOn"] = False
s.run(20)
r.check("P04 power lost after it was confirmed -> 210 + axis", s.v["bFault"] and s.v["uiAbortCode"] == 211, s.v["uiAbortCode"])
s.v["stStatus.HasError"] = True
s.run(20)
r.check("P05 axis error beats power lost -> 200 + axis; power command off",
        s.v["uiAbortCode"] == 201 and st["_fbPower"].pins["bSwitchOn"] is False, s.v["uiAbortCode"])
s.v["stStatus.DataValid"] = False
s.run(20)
r.check("P06 data invalid has top priority -> 230 + axis", s.v["uiAbortCode"] == 231, s.v["uiAbortCode"])

s, st = axis_power(2)
s.v.update({"bWantPower": True, "stStatus.PowerReady": True})
st["_fbPower"].out["bError"] = True
s.run(20)
r.check("P07 power command rejected -> 220 + axis", s.v["uiAbortCode"] == 222, s.v["uiAbortCode"])
st["_fbPower"].out["bError"] = False
s.run(20)
r.check("P08 next accepted command clears it", not s.v["bFault"] and s.v["uiAbortCode"] == 0)
s.v["bWantPower"] = False
s.v["stStatus.PowerOn"] = False
s.run(20)
r.check("P09 power switched off on purpose: no power-lost fault", not s.v["bFault"])
s.v["bReset"] = True
s.run(20)
r.check("P10 bReset drives the reset wrapper's Execute", st["_fbReset"].pins["bExecute"] is True)

# ===================== FB_ServoAxisMgr =====================


class AxisModel(Stub):
    """An axis: powers on POWER_SCANS after power is wanted and it is ready; off at once."""
    POWER_SCANS = 3

    def __init__(self, key):
        super().__init__(bFault=False, uiAbortCode=0)
        self.key, self.count, self.ready, self.moving = key, 0, True, False

    def step(self, pins, sim):
        f = f"astStatus[GVL_Axes.{self.key}]"
        want = pins["bWantPower"] and self.ready and not sim.v[f"{f}.HasError"]
        if want and not sim.v[f"{f}.PowerOn"]:
            self.count += 1
            if self.count >= self.POWER_SCANS:
                sim.v[f"{f}.PowerOn"], self.count = True, 0
        elif not want:
            sim.v[f"{f}.PowerOn"], self.count = False, 0
        sim.v[f"{f}.Standstill"] = not self.moving
        sim.v[f"{f}.PowerReady"] = self.ready


def axis_mgr():
    stubs = {"_fbAx1": AxisModel("AX1"), "_fbAx2": AxisModel("AX2"), "_fbVm": AxisModel("VM"),
             "_fbStateReq": Stub()}
    s = XSim(sys.argv[1], "FB_ServoAxisMgr", stubs=stubs, consts=CONSTS)
    for k in AXES:
        s.v.update({f"astStatus[GVL_Axes.{k}].{f}": False for f in FIELDS})
        s.v[f"astStatus[GVL_Axes.{k}].DataValid"] = True
        s.v[f"asAxisName[GVL_Axes.{k}]"] = k
        s.v[f"astStatus[GVL_Axes.{k}]"] = k          # whole-struct pin: only passed through
    return s, stubs


def run(s, ms, state):
    set_machine_state(s, state)
    s.run(ms)


def done(st):
    return st["_fbStateReq"].pins["bDone"]


def powered(s):
    return all(s.v[f"astStatus[GVL_Axes.{k}].PowerOn"] for k in AXES)


s, st = axis_mgr()
run(s, 100, "Off")
r.check("M01 Off: no power, done", not s.v["_bWantPower"] and done(st))
run(s, 10, "TurningOn")
r.check("M02 TurningOn: power wanted, not done until all powered", s.v["_bWantPower"] and not done(st))
run(s, 100, "TurningOn")
r.check("M03 all powered -> done in TurningOn", powered(s) and done(st))
ok = True
for state in ["Idle", "Starting", "Running", "Holding", "Hold", "UnHolding", "Stopping"]:
    run(s, 50, state)
    ok = ok and powered(s) and done(st)
r.check("M04 powered and done in Idle..Stopping", ok)

# Aborting: power stays on while an axis moves, torque-free after all are at rest (debounced)
st["_fbAx1"].moving = True
run(s, 50, "Running")                   # moving when the abort comes
run(s, 300, "Aborting")
r.check("M05 Aborting with an axis moving: still powered, not done", powered(s) and not done(st))
st["_fbAx1"].moving = False
run(s, 50, "Aborting")
r.check("M06 at rest < 100 ms: still powered (debounce)", powered(s))
run(s, 100, "Aborting")
r.check("M07 at rest 100 ms -> torque-free, done in Aborting", not any(
    s.v[f"astStatus[GVL_Axes.{k}].PowerOn"] for k in AXES) and done(st))
run(s, 100, "Aborted")
r.check("M08 Aborted: off, done", not s.v["_bWantPower"] and done(st))

# Resetting: reset issued to every axis, power back once ready, done when powered without error
run(s, 10, "Resetting")
r.check("M09 Resetting: reset Execute on every axis", all(st[n].pins["bReset"] for n in ["_fbAx1", "_fbAx2", "_fbVm"]))
run(s, 100, "Resetting")
r.check("M10 powered again -> done in Resetting", powered(s) and done(st))
run(s, 10, "Idle")
r.check("M11 reset Execute removed after Resetting", not any(st[n].pins["bReset"] for n in ["_fbAx1", "_fbAx2", "_fbVm"]))

# Not ready for power (DC bus down): waits, TurningOn not done
s, st = axis_mgr()
st["_fbAx2"].ready = False
run(s, 200, "TurningOn")
r.check("M12 Ax2 not ready for power: TurningOn not done", not done(st))

# Faults: first axis in order, abort only outside Aborting/Aborted/Resetting
s, st = axis_mgr()
run(s, 100, "TurningOn"); run(s, 20, "Running")
st["_fbVm"].out.update(bFault=True, uiAbortCode=202)
st["_fbAx2"].out.update(bFault=True, uiAbortCode=211)
run(s, 20, "Running")
p = st["_fbStateReq"].pins
r.check("M13 faults on Ax2 and VM -> Ax2's code first", (p["bAbort"], p["uiAbortCode"]) == (True, 211), p)
ok = True
for state in ["Aborting", "Aborted", "Resetting"]:
    run(s, 20, state)
    ok = ok and not st["_fbStateReq"].pins["bAbort"]
r.check("M14 no abort request in Aborting/Aborted/Resetting", ok)
s.v["astStatus[GVL_Axes.AX1].HasError"] = True
run(s, 50, "Resetting")
r.check("M15 Resetting with an axis error: not done", not done(st))

sys.exit(r.done())
