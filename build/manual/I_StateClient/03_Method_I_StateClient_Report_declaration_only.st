// I_StateClient: Method I_StateClient.Report (declaration only)
METHOD Report
VAR_INPUT
    eStateEcho  : E_MachineState;   // machine state the unit is acting on
    bDone       : BOOL;             // unit has finished eStateEcho
    bEnable     : BOOL;             // client takes part in the machine state
END_VAR
