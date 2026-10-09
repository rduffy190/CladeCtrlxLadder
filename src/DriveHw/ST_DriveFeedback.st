// DUT: ST_DriveFeedback
// Decoded drive status word (see Fn_DriveFeedback).
TYPE ST_DriveFeedback :
STRUCT
    bReadyForPower  : BOOL;     // bit 14 OR bit 15
    bUnderTorque    : BOOL;     // bit 14 AND bit 15
    bFault          : BOOL;     // bit 13
END_STRUCT
END_TYPE
