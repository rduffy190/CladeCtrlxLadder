"""ld_sim extended for this project's tests.

ld_sim runs contacts, coils, compares, MOVE and TON, and raises on anything else. The ladder
POUs here also call FBs on EN/ENO (ST helpers, ML_ wrappers, library FBs). A test replaces each
called instance with a Stub: a Python model that gets the pin values each call and sets the
instance's outputs. Pin expressions with arithmetic (e.g. `_uiReasonBase + INT_TO_UINT(iAxis)`)
are evaluated too. Names from outside the POU (GVL constants, library enums, struct fields of a
VAR_IN_OUT) must be given by the test through `consts` or `sim.v`, so nothing defaults silently.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".claude/skills/codesys-lad/scripts"))
from ld_sim import Sim, P  # noqa: E402

FUNCS = {"INT_TO_UINT": int, "DINT_TO_UINT": int, "ABS": abs}
IDENT = re.compile(r"[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*|\[[^\]]*\])*")


class Stub:
    """A sub-FB model. `out` holds its outputs; `step(pins, sim)` runs when the FB is called."""

    def __init__(self, **outputs):
        self.out = dict(outputs)
        self.pins = {}
        self.calls = 0

    def step(self, pins, sim):
        pass

    def __call__(self, pins, sim):
        self.pins = pins
        self.calls += 1
        self.step(pins, sim)


class XSim(Sim):
    def __init__(self, path, pou, stubs=None, consts=None, scan_ms=10):
        super().__init__(path, pou, scan_ms=scan_ms)
        self.consts.update(consts or {})
        self.stubs = stubs or {}
        for inst, stub in self.stubs.items():
            for pin, val in stub.out.items():
                self.v[f"{inst}.{pin}"] = val

    def literal(self, s):
        try:
            return super().literal(s)
        except KeyError:
            if not re.search(r"[-+*/(]", s):
                raise
            expr = IDENT.sub(lambda m: m.group(0) if m.group(0) in FUNCS
                             else repr(super(XSim, self).literal(m.group(0))), s)
            return eval(expr, {"__builtins__": {}}, FUNCS)

    def block(self, e, source):
        inst = e.get("instanceName")
        if inst not in self.stubs:
            return super().block(e, source)
        pins = {v.get("formalParameter"): source(v.find(f"{P}connectionPointIn"))
                for v in e.findall(f"{P}inputVariables/{P}variable")}
        en = pins.pop("EN", True)
        stub = self.stubs[inst]
        if en:
            stub(pins, self)
        for pin, val in stub.out.items():
            self.v[f"{inst}.{pin}"] = val
        for v in e.findall(f"{P}outputVariables/{P}variable"):
            target = v.findtext(f"{P}connectionPointOut/{P}expression")
            if target and v.get("formalParameter") in stub.out:
                self.v[target] = stub.out[v.get("formalParameter")]
        return {"ENO": bool(en), **stub.out}


MACHINE_STATES = ["Off", "TurningOn", "Idle", "Starting", "Running", "Stopping", "Holding", "Hold",
                  "UnHolding", "Aborting", "Aborted", "Resetting"]


def set_machine_state(sim, state, var="stMachineState"):
    """Drive an ST_MachineState input the way FB_StateManager fills it: the enum plus one BOOL per state."""
    sim.v[f"{var}.eState"] = MACHINE_STATES.index(state)
    for st in MACHINE_STATES:
        sim.v[f"{var}.b{st}"] = st == state


class Report:
    def __init__(self, title):
        self.title, self.failures = title, []
        print(f"== {title}")

    def check(self, name, ok, detail=""):
        print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"   {detail}"))
        if not ok:
            self.failures.append(name)

    def done(self):
        print(f"-- {self.title}: {'all passed' if not self.failures else f'{len(self.failures)} FAILED'}")
        return 1 if self.failures else 0
