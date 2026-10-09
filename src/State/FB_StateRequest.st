// FUNCTION_BLOCK: FB_StateRequest
// Standard wrapper every unit uses to talk to its state client: checks the client is
// attached and forwards requests, echo and done each call. Connect only the inputs used.

// ===== Declaration =====
FUNCTION_BLOCK FB_StateRequest
VAR_INPUT
    itfClient   : I_StateClient;    // attached client, e.g. GVL_State.aClients[GVL_State.CLIENT_DRIVE_HW]
    bEnable     : BOOL := TRUE;     // FALSE switches this unit out of the machine state
    bOn         : BOOL;             // request: turn machine on
    bOff        : BOOL;             // request: turn machine off
    bStart      : BOOL;             // request: start production
    bStop       : BOOL;             // request: controlled stop
    bHold       : BOOL;             // request: hold while TRUE
    bAbort      : BOOL;             // request: abort
    uiAbortCode : UINT;             // reason for bAbort
    bReset      : BOOL;             // request: reset after abort
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
END_VAR
VAR_OUTPUT
    bAttached   : BOOL;             // a client is attached
END_VAR
VAR
    _bAttached  : BOOL;
END_VAR

// ===== Implementation =====
_bAttached := itfClient <> 0;

IF _bAttached THEN
    itfClient.Request(
        bOn         := bOn,
        bOff        := bOff,
        bStart      := bStart,
        bStop       := bStop,
        bHold       := bHold,
        bAbort      := bAbort,
        uiAbortCode := uiAbortCode,
        bReset      := bReset);
    itfClient.Report(
        eStateEcho  := eStateEcho,
        bDone       := bDone,
        bEnable     := bEnable);
END_IF

// Outputs
bAttached := _bAttached;
