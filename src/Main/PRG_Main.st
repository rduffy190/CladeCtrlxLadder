// PRG_Main: reads the axis status, calls the state manager, broadcasts its state, then calls
// the units. Order matters: axis status first (it's an input), then the manager, so every
// unit sees the state settled on this scan.
// Adding a unit: a CLIENT_* constant in GVL_State (and MAX_CLIENTS), then one network here
// wiring its stMachineState and its client.
PROGRAM PRG_Main
VAR
    fbRtMem         : DL_MemUser;           // RT node access, shared by the axis map and reader
    stAxisRtConfig  : ST_AxisRtConfig;      // RT read configuration from fbAxisRtMap
    fbAxisRtMap     : FB_AxisRtMap;         // opens motion/realtime/cyclicStatusData, reads its map
    fbAxisRtRead    : FB_AxisRtRead;        // reads every axis in one access -> GVL_Axes.astStatus
    fbStateManager  : FB_StateManager;
    fbHmiStateReq   : FB_StateRequest;      // HMI is just another client
    fbDriveSupply   : FB_DriveSupplyMgr;
    fbServoAxes     : FB_ServoAxisMgr;
    fbServoMotion   : FB_ServoMotionSeq;
END_VAR
VAR CONSTANT
    HMI_ABORT_CODE  : UINT := 1;            // operator abort
    MODULO          : LREAL := 360.0;       // servo axes modulo
END_VAR

// ===== Axis status from the Data Layer RT (ST blocks) =====
NETWORK Axis RT map
// Opens the node and builds the config. A read failure (last scan) makes it close, reopen and remap.
    -> fbAxisRtMap(bEnable := TRUE, bReadFault := fbAxisRtRead.bError, asAxisName := GVL_Axes.asAxisName,
                   fbMem := fbRtMem, stConfig := stAxisRtConfig)

NETWORK Axis RT read
    -> fbAxisRtRead(fbMem := fbRtMem, astStatus := GVL_Axes.astStatus, stConfig := stAxisRtConfig)

// ===== State manager and broadcast =====
NETWORK State manager
// Its outputs are the broadcast: written to GVL_State here and nowhere else
    -> fbStateManager(aClients := GVL_State.aClients,
                      stMachineState => GVL_State.stMachineState, uiAbortCode => GVL_State.uiAbortCode,
                      iAbortClient => GVL_State.iAbortClient, eAbortFrom => GVL_State.eAbortFrom,
                      bAbortUnacked => GVL_State.bAbortUnacked,
                      iAbortTimeoutClient => GVL_State.iAbortTimeoutClient,
                      iNotDoneClient => GVL_State.iNotDoneClient)

// ===== Units =====
NETWORK HMI client
// Requests only, always done
    -> fbHmiStateReq(itfClient := GVL_State.aClients[GVL_State.CLIENT_HMI],
                     bOn := GVL_Hmi.bOnCmd, bOff := GVL_Hmi.bOffCmd, bStart := GVL_Hmi.bStartCmd,
                     bStop := GVL_Hmi.bStopCmd, bHold := GVL_Hmi.bHoldCmd, bAbort := GVL_Hmi.bAbortCmd,
                     uiAbortCode := HMI_ABORT_CODE, bReset := GVL_Hmi.bResetCmd,
                     eStateEcho := GVL_State.stMachineState.eState, bDone := TRUE)

NETWORK Drive hardware station
    -> fbDriveSupply(itfClient := GVL_State.aClients[GVL_State.CLIENT_DRIVE_HW],
                     stMachineState := GVL_State.stMachineState, wSupplyStatus := GVL_IO.wDI_SupplyStatus,
                     wSupplyCtrl := GVL_IO.wDO_SupplyCtrl, awDriveStatus := GVL_IO.awDI_DriveStatus,
                     awDriveDcBusCtrl := GVL_IO.awDO_DriveDcBusCtrl)

NETWORK Servo station: axes
    -> fbServoAxes(itfClient := GVL_State.aClients[GVL_State.CLIENT_SERVO_AXES],
                   stMachineState := GVL_State.stMachineState, asAxisName := GVL_Axes.asAxisName,
                   astStatus := GVL_Axes.astStatus)

NETWORK Servo station: motion
// Offsets: Ax1 at +offset, Ax2 at 360 - offset. The unit doesn't assume that relationship.
    -> fbServoMotion(itfClient := GVL_State.aClients[GVL_State.CLIENT_SERVO_MOTION],
                     stMachineState := GVL_State.stMachineState, asAxisName := GVL_Axes.asAxisName,
                     lrSpeedCmd := GVL_Hmi.lrSpeedCmd, lrAx1Offset := GVL_Hmi.lrSlaveOffset,
                     lrAx2Offset := MODULO - GVL_Hmi.lrSlaveOffset, astStatus := GVL_Axes.astStatus)
END_PROGRAM
