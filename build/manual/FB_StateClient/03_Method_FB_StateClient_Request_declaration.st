// FB_StateClient: Method FB_StateClient.Request: declaration
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
