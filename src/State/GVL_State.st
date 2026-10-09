// GVL: GVL_State
// Client array, client indexes and the broadcast machine state.
// The broadcast values are written only by PRG_Main, from FB_StateManager's outputs.
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    MAX_CLIENTS         : DINT := 4;
    CLIENT_HMI          : DINT := 1;
    CLIENT_DRIVE_HW     : DINT := 2;
    CLIENT_SERVO_AXES   : DINT := 3;
    CLIENT_SERVO_MOTION : DINT := 4;
END_VAR
VAR_GLOBAL
    aClients            : ARRAY[1..MAX_CLIENTS] OF FB_StateClient;  // index 0 is reserved for "no client"

    // Broadcast (copies of FB_StateManager outputs)
    stMachineState      : ST_MachineState;  // the machine state every unit follows: enum plus one BOOL per state
    uiAbortCode         : UINT;             // first abort cause, 0 = none
    iAbortClient        : DINT;             // client that caused the abort, 0 = none / manager
    eAbortFrom          : E_MachineState;   // state the machine aborted from
    bAbortUnacked       : BOOL;             // timeout abort: iAbortClient never acknowledged the state
    iAbortTimeoutClient : DINT;             // client that did not finish Aborting in time, 0 = none
    iNotDoneClient      : DINT;             // live: first client not done with the current state
END_VAR
