// DUT: ST_StateClientData
// Everything one client reports up to the state manager. All fields are levels.
TYPE ST_StateClientData :
STRUCT
    bEnabled    : BOOL;             // client takes part in AllDone and the request ORs (FALSE until a unit drives it)
    bOn         : BOOL;             // request: turn machine on
    bOff        : BOOL;             // request: turn machine off (acts in Idle)
    bStart      : BOOL;             // request: start production
    bStop       : BOOL;             // request: controlled stop
    bHold       : BOOL;             // request: hold while TRUE
    bAbort      : BOOL;             // request: abort
    uiAbortCode : UINT;             // reason for bAbort, unit specific
    bReset      : BOOL;             // request: reset after abort
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
END_STRUCT
END_TYPE
