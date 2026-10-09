// INTERFACE: I_StateClient
// Standard way for a unit to talk to its state client. Add the two methods below
// as child objects of the interface in the device tree.

// ===== Interface declaration =====
INTERFACE I_StateClient

// ===== Method I_StateClient.Request (declaration only) =====
METHOD Request
VAR_INPUT
    bOn         : BOOL;     // request: turn machine on
    bOff        : BOOL;     // request: turn machine off
    bStart      : BOOL;     // request: start production
    bStop       : BOOL;     // request: controlled stop
    bHold       : BOOL;     // request: hold while TRUE
    bAbort      : BOOL;     // request: abort
    uiAbortCode : UINT;     // reason for bAbort
    bReset      : BOOL;     // request: reset after abort
END_VAR

// ===== Method I_StateClient.Report (declaration only) =====
METHOD Report
VAR_INPUT
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
    bEnable     : BOOL;             // client takes part in the machine state
END_VAR
