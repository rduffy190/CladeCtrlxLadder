"""FB_StateManager test plan (central design §3, §4, §6), in the scan simulator.

    python3 tests/test_state_manager.py build/MotionLad_Import.xml

The client loop (FB_StateClientScan, ST) is replaced by a Python model of the same rules,
fed by model clients. A unit client echoes the machine state it saw on the previous scan
(as a real unit does) and reports done by a per-test rule.
"""
import sys
from simx import XSim, Stub, Report

STATES = ["Off", "TurningOn", "Idle", "Starting", "Running", "Stopping", "Holding", "Hold",
          "UnHolding", "Aborting", "Aborted", "Resetting"]
S = {n: i for i, n in enumerate(STATES)}
REQS = ["bOn", "bOff", "bStart", "bStop", "bHold", "bAbort", "bReset"]


class Client:
    def __init__(self, enabled=True, unit=True, done=lambda st: True):
        self.enabled, self.unit, self.done_rule = enabled, unit, done
        self.req = {r: False for r in REQS}
        self.code = 0
        self.echo, self.done = S["Off"], False
        self.ack = True             # FALSE: never takes the new state over (keeps the old echo)

    def follow(self, published):
        if self.ack or not self.unit:
            self.echo = published
        self.done = (not self.unit) or self.done_rule(self.echo)


class ClientScan(Stub):
    """Same rules as FB_StateClientScan."""

    def __init__(self, clients):
        super().__init__(bReqOn=False, bReqOff=False, bReqStart=False, bReqStop=False, bReqHold=False,
                         bReqAbort=False, bReqReset=False, bAllDone=True, iFirstAbortClient=0,
                         uiFirstAbortCode=0, iFirstNotDone=0, bFirstNotDoneUnacked=False)
        self.clients = clients

    def step(self, pins, sim):
        st = pins["eState"]
        published = sim.v.get("stMachineState.eState", S["Off"])   # the units saw last scan's broadcast (Off at power-up)
        o = {k: False for k in self.out if k.startswith("bReq")}
        o.update(bAllDone=True, iFirstAbortClient=0, uiFirstAbortCode=0, iFirstNotDone=0,
                 bFirstNotDoneUnacked=False)
        for i, c in sorted(self.clients.items()):
            c.follow(published)
            if not c.enabled:
                continue
            for r in REQS:
                o["bReq" + r[1:]] = o["bReq" + r[1:]] or c.req[r]
            if c.req["bAbort"] and o["iFirstAbortClient"] == 0:
                o["iFirstAbortClient"], o["uiFirstAbortCode"] = i, c.code
            if not (c.echo == st and c.done):
                o["bAllDone"] = False
                if o["iFirstNotDone"] == 0:
                    o["iFirstNotDone"], o["bFirstNotDoneUnacked"] = i, c.echo != st
        self.out.update(o)


def new(clients):
    return XSim(sys.argv[1], "FB_StateManager", stubs={"_fbClientScan": ClientScan(clients)})


def name(s):
    n = s.v["_eState"]
    return STATES[n] if 0 <= n < len(STATES) else n


struct_errors = []


def check_struct(s):
    """stMachineState: eState is the state, and exactly its BOOL is TRUE."""
    e = s.v["stMachineState.eState"]
    bits = [st for st in STATES if s.v.get(f"stMachineState.b{st}")]
    if e != s.v["_eState"] or (0 <= e < len(STATES) and bits != [STATES[e]]):
        struct_errors.append((s.now, e, bits))


def run(s, ms, until=None):
    """Run up to ms; stop early when the state is `until`. Returns the states passed through."""
    seen = [name(s)]
    for _ in range(ms // s.dt):
        s.scan()
        check_struct(s)
        if name(s) != seen[-1]:
            seen.append(name(s))
        if until and name(s) == until:
            break
    return seen


def drive(s, hmi, req, ms=200, until=None):
    for r in REQS:
        hmi.req[r] = r in req
    return run(s, ms, until)


r = Report("FB_StateManager")
HMI, UNIT, UNIT2 = 1, 2, 3


def standard():
    clients = {HMI: Client(unit=False), UNIT: Client(), UNIT2: Client(), 4: Client(enabled=False, done=lambda st: False)}
    return new(clients), clients


# 1 power-up: Off, holds with no request
s, c = standard(); seen = run(s, 1000)
r.check("01 starts in Off and stays there", seen == ["Off"] and s.v["stMachineState.eState"] == S["Off"], seen)

# 2 on -> TurningOn -> Idle once every unit is done; disabled client 4 is ignored
seen = drive(s, c[HMI], {"bOn"}, 300)
r.check("02 On -> TurningOn -> Idle", seen == ["Off", "TurningOn", "Idle"], seen)

# 3 on and off together in Off: stays Off
s2, c2 = standard(); seen = drive(s2, c2[HMI], {"bOn", "bOff"}, 300)
r.check("03 On with Off held stays Off", seen == ["Off"], seen)

# 4 start -> Starting -> Running
seen = drive(s, c[HMI], {"bStart"}, 300)
r.check("04 Start -> Starting -> Running", seen == ["Idle", "Starting", "Running"], seen)

# 5 hold -> Holding -> Hold, held while any client holds; resume when none does
c[UNIT2].req["bHold"] = True
seen = drive(s, c[HMI], {"bHold"}, 300)
r.check("05 Hold -> Holding -> Hold", seen == ["Running", "Holding", "Hold"], seen)
seen = drive(s, c[HMI], set(), 300)
r.check("06 Hold stays while another client still holds", seen == ["Hold"], seen)
c[UNIT2].req["bHold"] = False
seen = run(s, 300)
r.check("07 no hold -> UnHolding -> Running", seen == ["Hold", "UnHolding", "Running"], seen)

# 8 stop and hold together in Running: stop wins
seen = drive(s, c[HMI], {"bStop", "bHold"}, 300)
r.check("08 Stop beats Hold in Running -> Stopping -> Idle", seen == ["Running", "Stopping", "Idle"], seen)

# 9 stop held in Idle blocks start
seen = drive(s, c[HMI], {"bStop", "bStart"}, 300)
r.check("09 Start with Stop held stays Idle", seen == ["Idle"], seen)

# 10 off from Idle
seen = drive(s, c[HMI], {"bOff"}, 300)
r.check("10 Off in Idle -> Off", seen == ["Idle", "Off"], seen)

# 11 stop during Starting (units never done with Starting)
s, c = standard()
c[UNIT].done_rule = lambda st: st != S["Starting"]
drive(s, c[HMI], {"bOn"}, 300, until="Idle"); drive(s, c[HMI], {"bStart"}, 300)
seen = drive(s, c[HMI], {"bStop"}, 300)
r.check("11 Stop in Starting -> Stopping -> Idle", seen == ["Starting", "Stopping", "Idle"], seen)

# 12 abort from Running: first cause recorded, later causes ignored
s, c = standard()
drive(s, c[HMI], {"bOn"}, 300, until="Idle"); drive(s, c[HMI], {"bStart"}, 300, until="Running")
c[UNIT].done_rule = lambda st: st != S["Aborting"]          # keep it in Aborting for a while
c[UNIT2].req["bAbort"], c[UNIT2].code = True, 205
seen = drive(s, c[HMI], set(), 100)
rec = (s.v["uiAbortCode"], s.v["iAbortClient"], STATES[s.v["eAbortFrom"]])
r.check("12 abort request -> Aborting, cause recorded", seen == ["Running", "Aborting"] and rec == (205, UNIT2, "Running"), (seen, rec))
c[UNIT].req["bAbort"], c[UNIT].code = True, 101
run(s, 100)
rec2 = (s.v["uiAbortCode"], s.v["iAbortClient"])
r.check("13 a later abort doesn't overwrite the first cause", rec2 == (205, UNIT2), rec2)
c[UNIT].req["bAbort"] = False
c[UNIT].done_rule = lambda st: True
seen = run(s, 100)
r.check("14 Aborting -> Aborted when all done", seen == ["Aborting", "Aborted"], seen)
seen = drive(s, c[HMI], {"bReset"}, 300)
r.check("15 Reset with an abort still requested stays Aborted", seen == ["Aborted"] and s.v["uiAbortCode"] == 205, seen)
c[UNIT2].req["bAbort"] = False
seen = drive(s, c[HMI], {"bReset"}, 300)
cleared = (s.v["uiAbortCode"], s.v["iAbortClient"], s.v["eAbortFrom"])
r.check("16 Reset -> Resetting -> Idle, cause shown until Idle then cleared",
        seen == ["Aborted", "Resetting", "Idle"] and cleared == (0, 0, 0), (seen, cleared))

# 17 abort is ignored in Off
s, c = standard(); c[UNIT2].req["bAbort"] = True
seen = run(s, 300)
r.check("17 abort request in Off: stays Off", seen == ["Off"] and s.v["uiAbortCode"] == 0, seen)

# 18 timeout in Starting: unit busy (echo = Starting, not done)
s, c = standard()
c[UNIT2].done_rule = lambda st: st != S["Starting"]
drive(s, c[HMI], {"bOn"}, 300, until="Idle")
seen = drive(s, c[HMI], {"bStart"}, 61000, until="Aborting")
t = s.now
rec = (s.v["uiAbortCode"], s.v["iAbortClient"], s.v["bAbortUnacked"], STATES[s.v["eAbortFrom"]])
r.check("18 Starting timeout -> Aborting: code FFF0, client not done, acknowledged",
        seen[-1] == "Aborting" and rec == (0xFFF0, UNIT2, False, "Starting"), (seen, rec))

# 19 timeout in TurningOn: unit never acknowledges
s, c = standard()
c[UNIT].ack = False
seen = drive(s, c[HMI], {"bOn"}, 31000, until="Aborting")
rec = (s.v["uiAbortCode"], s.v["iAbortClient"], s.v["bAbortUnacked"])
r.check("19 TurningOn timeout, never acknowledged -> bAbortUnacked", seen[-1] == "Aborting" and rec == (0xFFF0, UNIT, True), (seen, rec))
t0 = s.now
seen = run(s, 11000, until="Aborted")
r.check("20 Aborting timeout -> Aborted after ~10 s, timeout client recorded",
        seen[-1] == "Aborted" and abs(s.now - t0 - 10000) <= 30 and s.v["iAbortTimeoutClient"] == UNIT,
        (seen, s.now - t0, s.v["iAbortTimeoutClient"]))

# 21 stale done: an old echo with done set never satisfies the new state
s, c = standard()
drive(s, c[HMI], {"bOn"}, 300, until="Idle"); drive(s, c[HMI], {"bStart"}, 300, until="Running")
c[UNIT].done_rule = lambda st: st == S["Holding"]
c[HMI].req["bHold"] = True
run(s, 300, until="Hold")
c[UNIT].ack = False             # the unit stops taking new states over: its echo stays Holding, with done
c[UNIT].echo = S["Holding"]; c[UNIT].done_rule = lambda st: True
c[HMI].req["bHold"] = False
seen = run(s, 1000)
r.check("21 stale done (echo Holding) doesn't complete UnHolding", seen == ["Hold", "UnHolding"], seen)

# 22 invalid state value -> Aborting with FFFF
s, c = standard()
drive(s, c[HMI], {"bOn"}, 300, until="Idle")
s.v["_eState"] = s.v["_eNextState"] = 42
run(s, 20)
rec = (name(s), s.v["uiAbortCode"], s.v["iAbortClient"])
r.check("22 invalid state -> Aborting, code FFFF", rec[0] in ("Aborting", "Aborted") and rec[1:] == (0xFFFF, 0), rec)

# 23 a stable state has no timeout
s, c = standard()
drive(s, c[HMI], {"bOn"}, 300, until="Idle")
seen = drive(s, c[HMI], set(), 120000)
r.check("23 Idle holds 120 s without timing out", seen == ["Idle"], seen)

# 24 every scan above: the published struct matches the state
r.check("24 stMachineState: eState and exactly one matching BOOL on every scan", not struct_errors, struct_errors[:3])

sys.exit(r.done())
