// DUT: ST_MachineState
// The broadcast machine state: the enum plus one BOOL per state, decoded once by
// FB_StateManager so units use contacts instead of decoding the enum themselves.
// Exactly one of the BOOLs is TRUE, and it always matches eState.
TYPE ST_MachineState :
STRUCT
    eState      : E_MachineState;   // the machine state (units echo this to their client)
    bOff        : BOOL;
    bTurningOn  : BOOL;
    bIdle       : BOOL;
    bStarting   : BOOL;
    bRunning    : BOOL;
    bStopping   : BOOL;
    bHolding    : BOOL;
    bHold       : BOOL;
    bUnHolding  : BOOL;
    bAborting   : BOOL;
    bAborted    : BOOL;
    bResetting  : BOOL;
END_STRUCT
END_TYPE
