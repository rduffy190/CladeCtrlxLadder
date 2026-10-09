// FB_StateManager: owns the machine state. Reads every client, runs the machine state machine
// and outputs the state for PRG_Main to broadcast through GVL_State.
// Ladder sequence: read clients -> jumps -> commit -> transitions -> commit -> state decode
// -> on change -> cyclic. The state decode is published as ST_MachineState, so units never
// decode the enum themselves. The client loop is FB_StateClientScan (ST), so adding a client
// never touches these networks.
// Design: design/Central_State_Management_Design.md
FUNCTION_BLOCK FB_StateManager
VAR_OUTPUT
    stMachineState      : ST_MachineState;  // the machine state: enum plus one BOOL per state
    uiAbortCode         : UINT;             // first abort cause, 0 = none
    iAbortClient        : DINT;             // client that caused the abort, 0 = none / manager
    eAbortFrom          : E_MachineState;   // state the machine aborted from
    bAbortUnacked       : BOOL;             // timeout abort: iAbortClient never acknowledged the state
    iAbortTimeoutClient : DINT;             // client that did not finish Aborting in time
    iNotDoneClient      : DINT;             // live: first client not done with the current state
END_VAR
VAR_IN_OUT
    aClients            : ARRAY[*] OF FB_StateClient;  // GVL_State.aClients; lower bound must be >= 1
END_VAR
VAR
    _eState             : E_MachineState;   // the state; stMachineState is only a copy
    _eNextState         : E_MachineState;   // written by jumps/transitions, committed to _eState after each section
    _eLastState         : E_MachineState;
    _bStateChanged      : BOOL;             // TRUE on the scan the state changed

    // Abort record: first cause only, cleared on entry to Idle
    _uiAbortCode        : UINT;
    _iAbortClient       : DINT;
    _eAbortFrom         : E_MachineState;
    _bAbortUnacked      : BOOL;
    _iAbortTimeoutClient: DINT;

    // Combined client data, rebuilt every scan by _fbClientScan
    _bReqOn             : BOOL;
    _bReqOff            : BOOL;
    _bReqStart          : BOOL;
    _bReqStop           : BOOL;
    _bReqHold           : BOOL;
    _bReqAbort          : BOOL;
    _bReqReset          : BOOL;
    _bAllDone           : BOOL;             // every enabled client is done with _eDoneState
    _eDoneState         : E_MachineState;   // state _bAllDone was evaluated for
    _bDoneHere          : BOOL;             // _bAllDone, and it was evaluated for the current _eState
    _iFirstAbortClient  : DINT;
    _uiFirstAbortCode   : UINT;
    _iFirstNotDone      : DINT;
    _bFirstNotDoneUnacked : BOOL;
    _bJumpsActive       : BOOL;             // abort/timeout jumps apply: not Off, Aborting or Aborted

    // State decoded after the commit: one BOOL per state
    _bStOff             : BOOL;
    _bStTurningOn       : BOOL;
    _bStIdle            : BOOL;
    _bStStarting        : BOOL;
    _bStRunning         : BOOL;
    _bStStopping        : BOOL;
    _bStHolding         : BOOL;
    _bStHold            : BOOL;
    _bStUnHolding       : BOOL;
    _bStAborting        : BOOL;
    _bStAborted         : BOOL;
    _bStResetting       : BOOL;

    _tStepTimeout       : TIME;             // timeout of the current state, T#0S = none
    _fbStepTimer        : TON;
    _fbClientScan       : FB_StateClientScan;
END_VAR
VAR CONSTANT
    NO_CLIENT                : DINT := 0;
    ABORT_CODE_NONE          : UINT := 0;
    ABORT_CODE_TIMEOUT       : UINT := 16#FFF0;    // a transitional state timed out
    ABORT_CODE_INVALID_STATE : UINT := 16#FFFF;    // unknown state value (e.g. after online change)

    TURNING_ON_TIMEOUT  : TIME := T#30S;
    STARTING_TIMEOUT    : TIME := T#60S;
    STOPPING_TIMEOUT    : TIME := T#30S;
    HOLDING_TIMEOUT     : TIME := T#30S;
    UNHOLDING_TIMEOUT   : TIME := T#30S;
    ABORTING_TIMEOUT    : TIME := T#10S;
    RESETTING_TIMEOUT   : TIME := T#30S;
END_VAR

// ===== 0. Read clients =====
NETWORK Read clients
// AllDone is evaluated for the state at the start of the scan
    -> _eDoneState := _eState

NETWORK Client scan
    -> _fbClientScan(eState := _eState, aClients := aClients,
                     bReqOn => _bReqOn, bReqOff => _bReqOff, bReqStart => _bReqStart,
                     bReqStop => _bReqStop, bReqHold => _bReqHold, bReqAbort => _bReqAbort,
                     bReqReset => _bReqReset, bAllDone => _bAllDone,
                     iFirstAbortClient => _iFirstAbortClient, uiFirstAbortCode => _uiFirstAbortCode,
                     iFirstNotDone => _iFirstNotDone, bFirstNotDoneUnacked => _bFirstNotDoneUnacked)

// ===== 1. Jumps: abort, then timeout =====
NETWORK J0 Jumps active
// The jumps apply in every state except Off, Aborting and Aborted
    [_eState <> E_MachineState.Off] [_eState <> E_MachineState.Aborting] [_eState <> E_MachineState.Aborted]
        -> _bJumpsActive

NETWORK J1 Abort request -> Aborting
// Only the first cause is recorded: the jumps don't run in Aborting or Aborted
    _bJumpsActive _bReqAbort
        -> _eNextState := E_MachineState.Aborting, _uiAbortCode := _uiFirstAbortCode,
           _iAbortClient := _iFirstAbortClient, _bAbortUnacked := FALSE, _eAbortFrom := _eState

NETWORK J2 Step timeout -> Aborting
// The step timer belongs to the current state, so this one rung covers every state's timeout
    _bJumpsActive /_bReqAbort _fbStepTimer.Q
        -> _eNextState := E_MachineState.Aborting, _uiAbortCode := ABORT_CODE_TIMEOUT,
           _iAbortClient := _iFirstNotDone, _bAbortUnacked := _bFirstNotDoneUnacked, _eAbortFrom := _eState

NETWORK J3 Aborting timeout -> Aborted
// Reaching a resettable state matters more than waiting forever
    [_eState = E_MachineState.Aborting] _fbStepTimer.Q
        -> _eNextState := E_MachineState.Aborted, _iAbortTimeoutClient := _iFirstNotDone

NETWORK Commit jumps
    -> _eState := _eNextState

// ===== 2. Transitions only =====
NETWORK All done with this state
// _bAllDone was evaluated for the state at the start of the scan. After a jump it says
// nothing about the new state, so the AllDone transitions use this instead.
    _bAllDone [_eDoneState = _eState] -> _bDoneHere

NETWORK T Off -> TurningOn
    [_eState = E_MachineState.Off] _bReqOn /_bReqOff -> _eNextState := E_MachineState.TurningOn

NETWORK T TurningOn -> Idle
    [_eState = E_MachineState.TurningOn] _bDoneHere -> _eNextState := E_MachineState.Idle

NETWORK T Idle -> Off
    [_eState = E_MachineState.Idle] _bReqOff -> _eNextState := E_MachineState.Off

NETWORK T Idle -> Starting
    [_eState = E_MachineState.Idle] /_bReqOff _bReqStart /_bReqStop -> _eNextState := E_MachineState.Starting

NETWORK T Starting -> Stopping
// A stop always wins, whether or not starting has completed
    [_eState = E_MachineState.Starting] _bReqStop -> _eNextState := E_MachineState.Stopping

NETWORK T Starting -> Running
    [_eState = E_MachineState.Starting] /_bReqStop _bDoneHere -> _eNextState := E_MachineState.Running

NETWORK T Running -> Stopping
// Stop wins over hold
    [_eState = E_MachineState.Running] _bReqStop -> _eNextState := E_MachineState.Stopping

NETWORK T Running -> Holding
    [_eState = E_MachineState.Running] /_bReqStop _bReqHold -> _eNextState := E_MachineState.Holding

NETWORK T Stopping -> Idle
    [_eState = E_MachineState.Stopping] _bDoneHere -> _eNextState := E_MachineState.Idle

NETWORK T Holding -> Hold
    [_eState = E_MachineState.Holding] _bDoneHere -> _eNextState := E_MachineState.Hold

NETWORK T Hold -> UnHolding
// Resume only when no client requests hold any more
    [_eState = E_MachineState.Hold] /_bReqHold -> _eNextState := E_MachineState.UnHolding

NETWORK T UnHolding -> Running
    [_eState = E_MachineState.UnHolding] _bDoneHere -> _eNextState := E_MachineState.Running

NETWORK T Aborting -> Aborted
    [_eState = E_MachineState.Aborting] _bDoneHere -> _eNextState := E_MachineState.Aborted

NETWORK T Aborted -> Resetting
// A held abort can't be reset away
    [_eState = E_MachineState.Aborted] _bReqReset /_bReqAbort -> _eNextState := E_MachineState.Resetting

NETWORK T Resetting -> Idle
    [_eState = E_MachineState.Resetting] _bDoneHere -> _eNextState := E_MachineState.Idle

NETWORK T Invalid state -> Aborting
// The CASE ELSE: any value past the last state (e.g. after an online change)
    [_eState > E_MachineState.Resetting]
        -> _eNextState := E_MachineState.Aborting, _uiAbortCode := ABORT_CODE_INVALID_STATE,
           _iAbortClient := NO_CLIENT, _bAbortUnacked := FALSE, _eAbortFrom := _eState

NETWORK Commit transitions
    -> _eState := _eNextState

// ===== State decode: one compare per rung, so later rungs use contacts =====
NETWORK Decode Off
    [_eState = E_MachineState.Off] -> _bStOff

NETWORK Decode TurningOn
    [_eState = E_MachineState.TurningOn] -> _bStTurningOn

NETWORK Decode Idle
    [_eState = E_MachineState.Idle] -> _bStIdle

NETWORK Decode Starting
    [_eState = E_MachineState.Starting] -> _bStStarting

NETWORK Decode Running
    [_eState = E_MachineState.Running] -> _bStRunning

NETWORK Decode Stopping
    [_eState = E_MachineState.Stopping] -> _bStStopping

NETWORK Decode Holding
    [_eState = E_MachineState.Holding] -> _bStHolding

NETWORK Decode Hold
    [_eState = E_MachineState.Hold] -> _bStHold

NETWORK Decode UnHolding
    [_eState = E_MachineState.UnHolding] -> _bStUnHolding

NETWORK Decode Aborting
    [_eState = E_MachineState.Aborting] -> _bStAborting

NETWORK Decode Aborted
    [_eState = E_MachineState.Aborted] -> _bStAborted

NETWORK Decode Resetting
    [_eState = E_MachineState.Resetting] -> _bStResetting

// ===== 3. On change: common actions, then entry actions =====
NETWORK State changed
    [_eState <> _eLastState] -> _bStateChanged

NETWORK Common: no timeout unless the new state sets one
    _bStateChanged -> _tStepTimeout := T#0S

NETWORK Entry Idle
// Idle means nothing is wrong: drop the abort record
    _bStateChanged _bStIdle
        -> _uiAbortCode := ABORT_CODE_NONE, _iAbortClient := NO_CLIENT, _eAbortFrom := E_MachineState.Off,
           _bAbortUnacked := FALSE, _iAbortTimeoutClient := NO_CLIENT

NETWORK Entry TurningOn
    _bStateChanged _bStTurningOn -> _tStepTimeout := TURNING_ON_TIMEOUT

NETWORK Entry Starting
    _bStateChanged _bStStarting -> _tStepTimeout := STARTING_TIMEOUT

NETWORK Entry Stopping
    _bStateChanged _bStStopping -> _tStepTimeout := STOPPING_TIMEOUT

NETWORK Entry Holding
    _bStateChanged _bStHolding -> _tStepTimeout := HOLDING_TIMEOUT

NETWORK Entry UnHolding
    _bStateChanged _bStUnHolding -> _tStepTimeout := UNHOLDING_TIMEOUT

NETWORK Entry Aborting
    _bStateChanged _bStAborting -> _tStepTimeout := ABORTING_TIMEOUT

NETWORK Entry Resetting
    _bStateChanged _bStResetting -> _tStepTimeout := RESETTING_TIMEOUT

NETWORK Remember state
    -> _eLastState := _eState

// ===== 4. Cyclic: sub-FBs, then outputs last =====
NETWORK Step timer
// Off for the change scan, so it restarts in every new state; stable states have no timeout
    [_tStepTimeout > T#0S] /_bStateChanged _fbStepTimer(PT := _tStepTimeout)

// The logic above never reads its own outputs
NETWORK Out state Off
    _bStOff -> stMachineState.bOff

NETWORK Out state TurningOn
    _bStTurningOn -> stMachineState.bTurningOn

NETWORK Out state Idle
    _bStIdle -> stMachineState.bIdle

NETWORK Out state Starting
    _bStStarting -> stMachineState.bStarting

NETWORK Out state Running
    _bStRunning -> stMachineState.bRunning

NETWORK Out state Stopping
    _bStStopping -> stMachineState.bStopping

NETWORK Out state Holding
    _bStHolding -> stMachineState.bHolding

NETWORK Out state Hold
    _bStHold -> stMachineState.bHold

NETWORK Out state UnHolding
    _bStUnHolding -> stMachineState.bUnHolding

NETWORK Out state Aborting
    _bStAborting -> stMachineState.bAborting

NETWORK Out state Aborted
    _bStAborted -> stMachineState.bAborted

NETWORK Out state Resetting
    _bStResetting -> stMachineState.bResetting

NETWORK Out copies
    -> stMachineState.eState := _eState, uiAbortCode := _uiAbortCode, iAbortClient := _iAbortClient,
       eAbortFrom := _eAbortFrom, bAbortUnacked := _bAbortUnacked,
       iAbortTimeoutClient := _iAbortTimeoutClient, iNotDoneClient := _iFirstNotDone
END_FUNCTION_BLOCK
