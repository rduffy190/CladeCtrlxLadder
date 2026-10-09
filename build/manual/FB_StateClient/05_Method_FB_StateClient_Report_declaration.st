// FB_StateClient: Method FB_StateClient.Report: declaration
METHOD Report
VAR_INPUT
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
    bEnable     : BOOL;             // client takes part in the machine state
END_VAR
