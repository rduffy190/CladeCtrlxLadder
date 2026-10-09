// FB_StateClient: Declaration
FUNCTION_BLOCK FB_StateClient IMPLEMENTS I_StateClient
VAR
    _stData     : ST_StateClientData;   // written by Request/Report, read by the manager via Data
END_VAR
