// FUNCTION_BLOCK: FB_StateClient
// The actual client. Holds one unit's requests, echo and done for FB_StateManager.
// Instances live in GVL_State.aClients; units reach them only through FB_StateRequest.
// Child objects: methods Request and Report, property Data (Get only).

// ===== Declaration =====
FUNCTION_BLOCK FB_StateClient IMPLEMENTS I_StateClient
VAR
    _stData     : ST_StateClientData;   // written by Request/Report, read by the manager via Data
END_VAR

// ===== Implementation =====
// (empty: the client is a data holder, never called cyclically)


// ===== Method FB_StateClient.Request: declaration =====
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

// ===== Method FB_StateClient.Request: implementation =====
// Every call overwrites all requests, so a released input releases its request.
_stData.bOn         := bOn;
_stData.bOff        := bOff;
_stData.bStart      := bStart;
_stData.bStop       := bStop;
_stData.bHold       := bHold;
_stData.bAbort      := bAbort;
_stData.uiAbortCode := uiAbortCode;
_stData.bReset      := bReset;


// ===== Method FB_StateClient.Report: declaration =====
METHOD Report
VAR_INPUT
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
    bEnable     : BOOL;             // client takes part in the machine state
END_VAR

// ===== Method FB_StateClient.Report: implementation =====
_stData.eStateEcho := eStateEcho;
_stData.bDone      := bDone;
_stData.bEnabled   := bEnable;


// ===== Property FB_StateClient.Data: declaration =====
PROPERTY Data : ST_StateClientData

// ===== Property FB_StateClient.Data, Get: implementation =====
Data := _stData;
