// DUT: E_MachineState
// Central machine state, broadcast by FB_StateManager through GVL_State.stMachineState.eState.
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_MachineState :
(
    Off := 0,
    TurningOn,
    Idle,
    Starting,
    Running,
    Stopping,
    Holding,
    Hold,
    UnHolding,
    Aborting,
    Aborted,
    Resetting
);
END_TYPE
