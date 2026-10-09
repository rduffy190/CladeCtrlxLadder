// FUNCTION_BLOCK: FB_DriveStatusScan
// Reads the status word of every drive on the supply and combines them for FB_DriveSupplyMgr:
// all ready for power, any under torque, any fault, and the abort code of the first faulted
// drive. Kept in ST because it loops over the drive array, so adding a drive is an I/O change only.
// Design: design/Unit_DriveHardwareStation_Design.md §2

// ===== Declaration =====
FUNCTION_BLOCK FB_DriveStatusScan
VAR_INPUT
    uiFaultCodeBase     : UINT;     // abort code of drive 0; drive i reports uiFaultCodeBase + i
END_VAR
VAR_OUTPUT
    bAllReadyForPower   : BOOL;     // every drive has bit 14 or bit 15
    bAnyUnderTorque     : BOOL;     // some drive has bits 14 and 15
    bAnyFault           : BOOL;     // some drive has bit 13
    uiFaultCode         : UINT;     // uiFaultCodeBase + index of the first faulted drive, 0 = none
END_VAR
VAR_IN_OUT CONSTANT
    awDriveStatus       : ARRAY[*] OF WORD; // drive status words, one per drive, numbered from 0
END_VAR
VAR
    _stDrive            : ST_DriveFeedback;
    _bAllReady          : BOOL;
    _bAnyTorque         : BOOL;
    _bAnyFault          : BOOL;
    _uiFaultCode        : UINT;
    _iDrive             : DINT;
END_VAR
VAR CONSTANT
    CODE_NONE           : UINT := 0;
END_VAR

// ===== Implementation =====
_bAllReady   := TRUE;
_bAnyTorque  := FALSE;
_bAnyFault   := FALSE;
_uiFaultCode := CODE_NONE;
FOR _iDrive := LOWER_BOUND(awDriveStatus, 1) TO UPPER_BOUND(awDriveStatus, 1) DO
    _stDrive := Fn_DriveFeedback(wStatus := awDriveStatus[_iDrive]);
    _bAllReady  := _bAllReady AND _stDrive.bReadyForPower;
    _bAnyTorque := _bAnyTorque OR _stDrive.bUnderTorque;
    IF _stDrive.bFault AND NOT _bAnyFault THEN
        _uiFaultCode := uiFaultCodeBase + DINT_TO_UINT(_iDrive);
    END_IF
    _bAnyFault := _bAnyFault OR _stDrive.bFault;
END_FOR

// Outputs
bAllReadyForPower := _bAllReady;
bAnyUnderTorque   := _bAnyTorque;
bAnyFault         := _bAnyFault;
uiFaultCode       := _uiFaultCode;
