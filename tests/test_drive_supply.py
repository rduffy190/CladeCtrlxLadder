"""FB_DriveSupplyMgr test plan (drive hardware design §3-§6), in the scan simulator.

    python3 tests/test_drive_supply.py build/MotionLad_Import.xml

Sub-FBs are models: the drive status scan is set by the test, the supply unit
(MB_PowerSupplyDriveIntegrated) reaches its target mode SUPPLY_SCANS scans after it is
enabled with that target, and the state client records what it is sent.
"""
import sys
from simx import XSim, Stub, Report, set_machine_state

STATES = ["Off", "TurningOn", "Idle", "Starting", "Running", "Stopping", "Holding", "Hold",
          "UnHolding", "Aborting", "Aborted", "Resetting"]
S = {n: i for i, n in enumerate(STATES)}
# Library enums: values only need to be distinct for the test
CONSTS = {"MB_POWERSUPPLY_ACTUAL_MODE.OPERATION_MODE": 1, "MB_POWERSUPPLY_ACTUAL_MODE.MAINS_OFF": 2,
          "MB_POWERSUPPLY_ACTUAL_MODE.TRANSITION": 3,
          "MB_POWERSUPPLY_TARGET_MODE.OPERATION_MODE": 11, "MB_POWERSUPPLY_TARGET_MODE.MAINS_OFF_NO_DISCHARGE": 12}
SUPPLY_SCANS = 5


class Supply(Stub):
    def __init__(self):
        super().__init__(ActualMode=CONSTS["MB_POWERSUPPLY_ACTUAL_MODE.MAINS_OFF"], PowerSupplyError=False, Error=False)
        self.count, self.fault = 0, False

    def step(self, pins, sim):
        on = pins["TargetMode"] == CONSTS["MB_POWERSUPPLY_TARGET_MODE.OPERATION_MODE"]
        want = CONSTS["MB_POWERSUPPLY_ACTUAL_MODE.OPERATION_MODE" if on and pins["Enable"] else "MB_POWERSUPPLY_ACTUAL_MODE.MAINS_OFF"]
        if self.out["ActualMode"] != want:
            self.count += 1
            if self.count >= SUPPLY_SCANS:
                self.out["ActualMode"], self.count = want, 0
        else:
            self.count = 0
        self.out["PowerSupplyError"] = self.fault
        if not pins["Enable"]:
            self.out["Error"] = False           # disabling clears the FB's error


def new():
    stubs = {"_fbDriveStatus": Stub(bAllReadyForPower=False, bAnyUnderTorque=False, bAnyFault=False, uiFaultCode=0),
             "_fbSupply": Supply(), "_fbDcBus": Stub(), "_fbStateReq": Stub()}
    return XSim(sys.argv[1], "FB_DriveSupplyMgr", stubs=stubs, consts=CONSTS), stubs


def run(s, ms, state):
    set_machine_state(s, state)
    s.run(ms)


def client(st):
    p = st["_fbStateReq"].pins
    return p["bDone"], p["bAbort"], p["uiAbortCode"], p["eStateEcho"]


def in_op(s):
    return s.v["_bSupplyInOp"]


r = Report("FB_DriveSupplyMgr")

# 1 Off: supply off, done
s, st = new(); run(s, 200, "Off")
r.check("01 Off: supply off, done", not s.v["_bSupplyCmd"] and client(st)[0], client(st))

# 2 TurningOn waits for every drive ready for power
run(s, 500, "TurningOn")
r.check("02 TurningOn, drives not ready: supply not commanded, not done", not s.v["_bSupplyCmd"] and not client(st)[0])
st["_fbDriveStatus"].out["bAllReadyForPower"] = True
run(s, 200, "TurningOn")
r.check("03 drives ready -> supply on, DC bus power, done",
        in_op(s) and st["_fbDcBus"].pins["bDcBusPower"] and client(st)[0] and client(st)[3] == S["TurningOn"])

# 4 stays on through the running states, even when readiness changes
st["_fbDriveStatus"].out["bAllReadyForPower"] = False          # e.g. drives now in "under torque"
st["_fbDriveStatus"].out["bAnyUnderTorque"] = True
ok = True
for state in ["Idle", "Starting", "Running", "Holding", "Hold", "UnHolding", "Stopping"]:
    run(s, 100, state)
    ok = ok and in_op(s) and client(st)[0]
r.check("04 on and done in Idle..Stopping, holds itself on", ok)

# 5 Aborting: stays on while any axis is under torque, then off
run(s, 300, "Aborting")
r.check("05 Aborting with torque: supply stays on, not done", s.v["_bSupplyCmd"] and in_op(s) and not client(st)[0])
st["_fbDriveStatus"].out["bAnyUnderTorque"] = False
run(s, 200, "Aborting")
r.check("06 torque-free -> supply off, done in Aborting", not s.v["_bSupplyCmd"] and s.v["_bSupplyOff"] and client(st)[0])

# 7 Off from Idle under torque waits for torque-free
s, st = new()
st["_fbDriveStatus"].out["bAllReadyForPower"] = True
run(s, 200, "TurningOn"); run(s, 100, "Idle")
st["_fbDriveStatus"].out["bAnyUnderTorque"] = True
run(s, 300, "Off")
r.check("07 Off under torque: supply held on, not done", s.v["_bSupplyCmd"] and not client(st)[0])
st["_fbDriveStatus"].out["bAnyUnderTorque"] = False
run(s, 200, "Off")
r.check("08 Off torque-free: supply off, done", not s.v["_bSupplyCmd"] and client(st)[0])

# 9 drive fault in Running -> abort with the drive code
s, st = new()
st["_fbDriveStatus"].out["bAllReadyForPower"] = True
run(s, 200, "TurningOn"); run(s, 100, "Running")
st["_fbDriveStatus"].out.update(bAnyFault=True, uiFaultCode=111)
run(s, 20, "Running")
r.check("09 drive 1 fault in Running -> abort 111", client(st)[1:3] == (True, 111), client(st))

# 10 supply fault beats a drive fault
st["_fbSupply"].fault = True
run(s, 20, "Running")
r.check("10 supply fault has priority -> abort 101", client(st)[1:3] == (True, 101), client(st))

# 11 no fault aborts in Aborting / Aborted / Resetting (code still shown)
ok = True
for state in ["Aborting", "Aborted", "Resetting"]:
    run(s, 50, state)
    ok = ok and not client(st)[1] and s.v["uiAbortCode"] == 101
r.check("11 no abort request in Aborting/Aborted/Resetting", ok)

# 12 Resetting: done only when faults are gone and the supply is back in operation
r.check("12 Resetting with faults: not done", not client(st)[0])
st["_fbSupply"].fault = False
st["_fbDriveStatus"].out.update(bAnyFault=False, uiFaultCode=0)
run(s, 300, "Resetting")
r.check("13 faults cleared -> supply back on, done in Resetting", in_op(s) and client(st)[0] and s.v["uiAbortCode"] == 0)

# 14 supply control error (mode timeout) aborts outside Aborting; Resetting drops Enable to clear it
s, st = new()
st["_fbDriveStatus"].out["bAllReadyForPower"] = True
run(s, 30, "TurningOn")
st["_fbSupply"].out["Error"] = True
run(s, 20, "TurningOn")
r.check("14 supply control error in TurningOn -> abort 100", client(st)[1:3] == (True, 100), client(st))
run(s, 20, "Resetting")
r.check("15 Resetting with control error: Enable off clears it", not s.v["_bSupplyEnable"] or not st["_fbSupply"].out["Error"])
run(s, 300, "Resetting")
r.check("16 then supply comes on and Resetting is done", in_op(s) and client(st)[0])

# 17 the outputs are copies
r.check("17 diag outputs follow internals", s.v["bSupplyInOperation"] == in_op(s) and s.v["bAllReadyForPower"])

sys.exit(r.done())
