// FUNCTION_BLOCK: FB_StateClientScan
// Section 0 of FB_StateManager: reads every client and combines them. Kept in ST because it
// loops over the client array, so adding a client never touches the ladder.
// Requests are ORed across the enabled clients. AllDone is the AND of
// (echo = eState AND done) across the enabled clients. Also returns the first client
// requesting an abort (index and code) and the first client not done, for diagnostics.
// Design: design/Central_State_Management_Design.md §6

// ===== Declaration =====
FUNCTION_BLOCK FB_StateClientScan
VAR_INPUT
    eState              : E_MachineState;   // state the clients are checked against (the manager's state at the start of the scan)
END_VAR
VAR_OUTPUT
    bReqOn              : BOOL;     // some enabled client requests on
    bReqOff             : BOOL;     // some enabled client requests off
    bReqStart           : BOOL;     // some enabled client requests start
    bReqStop            : BOOL;     // some enabled client requests stop
    bReqHold            : BOOL;     // some enabled client requests hold
    bReqAbort           : BOOL;     // some enabled client requests abort
    bReqReset           : BOOL;     // some enabled client requests reset
    bAllDone            : BOOL;     // every enabled client echoes eState and is done
    iFirstAbortClient   : DINT;     // first client requesting an abort, 0 = none
    uiFirstAbortCode    : UINT;     // its abort code
    iFirstNotDone       : DINT;     // first enabled client not done with eState, 0 = none
    bFirstNotDoneUnacked: BOOL;     // that client hasn't echoed eState yet (never acknowledged)
END_VAR
VAR_IN_OUT
    aClients            : ARRAY[*] OF FB_StateClient;  // GVL_State.aClients; lower bound must be >= 1
END_VAR
VAR
    _bReqOn             : BOOL;
    _bReqOff            : BOOL;
    _bReqStart          : BOOL;
    _bReqStop           : BOOL;
    _bReqHold           : BOOL;
    _bReqAbort          : BOOL;
    _bReqReset          : BOOL;
    _bAllDone           : BOOL;
    _iFirstAbortClient  : DINT;
    _uiFirstAbortCode   : UINT;
    _iFirstNotDone      : DINT;
    _bFirstNotDoneUnacked : BOOL;
    _iClient            : DINT;
    _stClient           : ST_StateClientData;
END_VAR
VAR CONSTANT
    NO_CLIENT           : DINT := 0;
    ABORT_CODE_NONE     : UINT := 0;
END_VAR

// ===== Implementation =====
_bReqOn    := FALSE;
_bReqOff   := FALSE;
_bReqStart := FALSE;
_bReqStop  := FALSE;
_bReqHold  := FALSE;
_bReqAbort := FALSE;
_bReqReset := FALSE;
_bAllDone  := TRUE;
_iFirstAbortClient    := NO_CLIENT;
_uiFirstAbortCode     := ABORT_CODE_NONE;
_iFirstNotDone        := NO_CLIENT;
_bFirstNotDoneUnacked := FALSE;

FOR _iClient := LOWER_BOUND(aClients, 1) TO UPPER_BOUND(aClients, 1) DO
    _stClient := aClients[_iClient].Data;
    IF _stClient.bEnabled THEN
        _bReqOn    := _bReqOn    OR _stClient.bOn;
        _bReqOff   := _bReqOff   OR _stClient.bOff;
        _bReqStart := _bReqStart OR _stClient.bStart;
        _bReqStop  := _bReqStop  OR _stClient.bStop;
        _bReqHold  := _bReqHold  OR _stClient.bHold;
        _bReqAbort := _bReqAbort OR _stClient.bAbort;
        _bReqReset := _bReqReset OR _stClient.bReset;

        IF _stClient.bAbort AND _iFirstAbortClient = NO_CLIENT THEN
            _iFirstAbortClient := _iClient;
            _uiFirstAbortCode  := _stClient.uiAbortCode;
        END_IF

        // Done only counts for eState: a stale done from an old echo is ignored
        IF NOT (_stClient.eStateEcho = eState AND _stClient.bDone) THEN
            _bAllDone := FALSE;
            IF _iFirstNotDone = NO_CLIENT THEN
                _iFirstNotDone        := _iClient;
                _bFirstNotDoneUnacked := _stClient.eStateEcho <> eState;
            END_IF
        END_IF
    END_IF
END_FOR

// Outputs
bReqOn               := _bReqOn;
bReqOff              := _bReqOff;
bReqStart            := _bReqStart;
bReqStop             := _bReqStop;
bReqHold             := _bReqHold;
bReqAbort            := _bReqAbort;
bReqReset            := _bReqReset;
bAllDone             := _bAllDone;
iFirstAbortClient    := _iFirstAbortClient;
uiFirstAbortCode     := _uiFirstAbortCode;
iFirstNotDone        := _iFirstNotDone;
bFirstNotDoneUnacked := _bFirstNotDoneUnacked;
