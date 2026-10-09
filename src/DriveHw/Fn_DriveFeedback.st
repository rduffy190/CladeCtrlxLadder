// FUNCTION: Fn_DriveFeedback
// Decodes a drive status word into ready-for-power, under-torque and fault.
//   bits 15/14: 00 not ready, 01 ready for power, 10 power section ready (torque-free), 11 under torque
//   bit 13:     fault

// ===== Declaration =====
FUNCTION Fn_DriveFeedback : ST_DriveFeedback
VAR_INPUT
    wStatus     : WORD;     // drive status word
END_VAR
VAR CONSTANT
    MASK_FAULT  : WORD := 16#2000;  // bit 13
    MASK_BIT_14 : WORD := 16#4000;  // bit 14
    MASK_BIT_15 : WORD := 16#8000;  // bit 15
END_VAR

// ===== Implementation =====
Fn_DriveFeedback.bReadyForPower := (wStatus AND (MASK_BIT_14 OR MASK_BIT_15)) <> 0;
Fn_DriveFeedback.bUnderTorque   := (wStatus AND (MASK_BIT_14 OR MASK_BIT_15)) = (MASK_BIT_14 OR MASK_BIT_15);
Fn_DriveFeedback.bFault         := (wStatus AND MASK_FAULT) <> 0;
