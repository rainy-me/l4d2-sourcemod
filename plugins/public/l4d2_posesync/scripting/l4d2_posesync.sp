/*
 * l4d2_posesync.sp - pose parameter and animation lag compensation for Left 4 Dead 2
 *
 * The problem
 *   L4D2's CLagCompensationManager stores origin, angles, bounds, the base sequence / cycle and
 *   the overlay layers of every lag compensated entity each tick and rewinds them when a player
 *   shoots or shoves. It never stores m_flPoseParameter, so the rewound hitboxes combine the old
 *   position with the present aim, move blend and so on. For gunshots it does not rewind the
 *   sequence, cycle or layers either (see point 5). On top of that, the client does not draw
 *   other entities at the engine's target time in every respect: it interpolates their position,
 *   but plays their animations on its own clock, crossfades sequence changes, and builds some
 *   values (eye angles, body yaw, common infected frames) its own way. The server's rewound
 *   skeleton and the one the shooter saw therefore disagree.
 *
 * How the plugin works
 *   1. RecordDataIntoTrack (post): whenever the engine stores a lag record for an entity, the
 *      plugin stores a record of its own under the same simulation time: pose parameters, origin,
 *      sequence, cycle, playback rate, the animstate render yaw, the networked eye angles, the
 *      overlay layers and the common infected sequence start time.
 *   2. BacktrackEntity (pre): from those records, the plugin builds what the shooter's client drew
 *      and writes it onto the entity before the engine builds the rewound hitboxes:
 *      - pose parameters at the target time; eye-driven ones (aim, body yaw) from the networked
 *        eye angles at the time the client draws
 *      - origin and angles at the time the client draws (whole interpolation ticks)
 *      - main sequence and cycle on the client's animation clock
 *   3. BacktrackEntity (post): after the engine wrote its own sequence and cycle, they are
 *      replaced with the client-clock ones, the client's sequence crossfade is added in free
 *      overlay slots, the entity is put where the shooter's client drew it (a Hermite curve
 *      through the states it received, see MoveToClientPosition), the move blends are rebuilt from
 *      the client's speed estimate, and the bone cache and bullet broad-phase bounds are refreshed.
 *   4. FinishLagCompensation: before it runs, the borrowed overlay slots are emptied (the engine
 *      puts its layers back inside it); after it, everything else the plugin changed is put back.
 *   5. Gaps in what the engine rewinds at all (each optional):
 *      - CTerrorPlayer::WantsLagCompensationOnEntity: keeps a swing compensated after the button
 *        is released; rewinds a survivor ridden by a Jockey so the Jockey, which is attached to
 *        it, moves along
 *      - CLagCompensationManager::StartLagCompensation: asks for the animation rewind for gunshots
 *      - BacktrackEntity refusals over sparse records the client interpolated across
 *
 * Windows (server.dll md5 533888fbb4e5ed534b172470613a3017) and Linux (server_srv.so md5
 * bf54b537f4707f0c602208c427ec62df, server.so md5 e962508781885d7b0d871d79e456b03d); every
 * platform-dependent value is in the gamedata.
 * Requires SourceMod 1.11+ (built-in DHooks).
 */

#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <profiler>
#include <dhooks>

#define PLUGIN_VERSION   "1.0"
#define GAMEDATA         "l4d2_posesync.games"

#define MAXPOSE          24          // m_flPoseParameter[24]
#define MAX_ENTS         2049
#define MAX_RING         512
#define POSE_NAME_LEN    32
#define MAX_INCLUDES     64

// One history record per entity and simulation time (cells of an ArrayList block).
#define REC_SIM          0
#define REC_MODEL        1
#define REC_POSE         2
#define REC_ORG          (2 + MAXPOSE)          // abs origin x,y,z (for the client velocity emulation)
#define REC_SEQ          (REC_ORG + 3)          // main sequence, cycle, playback rate, new-sequence parity
#define REC_CYCLE        (REC_SEQ + 1)
#define REC_RATE         (REC_SEQ + 2)
#define REC_PARITY       (REC_SEQ + 3)
#define REC_RYAW         (REC_SEQ + 4)          // players: animstate render yaw (the yaw the server's bones are built with)
#define REC_HASYAW       (REC_SEQ + 5)
#define REC_RESET        (REC_SEQ + 6)          // players: EF_NOINTERP / no-interp parity bump at this record (client resets its interpolation)
#define REC_SEQSTART     (REC_SEQ + 7)          // common infected / witch: m_sequenceStartTime; players: m_mainSequenceStartTime (-1 = none)
#define REC_EYEP         (REC_SEQ + 8)          // players: networked m_angEyeAngles[0] (what the client aims with)
#define REC_EYEY         (REC_SEQ + 9)          // players: networked m_angEyeAngles[1]
#define REC_HASEYE       (REC_SEQ + 10)
#define REC_NLAYERS      (REC_SEQ + 11)         // players: overlay layers recorded (slot order)
#define REC_AYAW         (REC_SEQ + 12)         // entity abs yaw (the sparse record bridge moves common infected with it)
#define REC_CICOUNT      (REC_SEQ + 13)         // common infected: entries of m_clientAnimatedOverlay recorded
#define REC_CI           (REC_SEQ + 14)         // per entry: sequence, start time, order | looping << 8
#define REC_CISTRIDE     3
#define MAX_CI_LAYERS    6                      // DT_Infected sends at most 6
#define REC_TICK         (REC_CI + MAX_CI_LAYERS * REC_CISTRIDE)   // server tick the record was made in
#define REC_REAL         (REC_TICK + 1)         // 1 = the simulation time moved (a sample the client interpolates), 0 = a sequence change recorded without one
#define REC_VEL          (REC_TICK + 2)         // abs velocity x,y,z (what the server's animstate moved with)
#define REC_LAYERS       (REC_VEL + 3)          // players, per slot: flags, sequence, cycle, weight, order
#define REC_LSTRIDE      5
#define MAX_REC_LAYERS   16
#define REC_SIZE         (REC_LAYERS + MAX_REC_LAYERS * REC_LSTRIDE)

// Per-sequence info block, read from the model: [flags, fadein, fadeout, cycle rate, kind].
#define SI_FLAGS   0
#define SI_FADEIN  1
#define SI_FADEOUT 2
#define SI_RATE    3
#define SI_KIND    4    // SK_* bits, worked out from the activity once when the model is read
#define SI_SIZE    5
#define SK_MOVE    1    // movement sequence (see IsMoveSeq)
#define SK_EYELOCK 2    // the client's animstate holds its eye angles (see IsEyeLockAct)
#define SK_RANDOM  4    // client.dll starts it at a random cycle on common infected (see IsRandomStartAct)
#define SK_POUNCE  8    // ACT_TERROR_HUNTER_POUNCE
#define SK_JOCKEYRIDE 16 // ACT_TERROR_JOCKEY_RIDE (the animstate's move blend has its own smoothed branch for it)
#define SK_NOGS    32   // the client's GetCurrentMaxGroundSpeed is 0 for it, so its move blend is 0 (see ActZeroGroundSpeed)
#define SK_VEL     64   // the animstate computes vert_vel / horiz_vel in it (0x2eb / 0x2ec / 0x20d in server.dll and client.dll)

// Per-sequence movement block (only for sequences with motion), read from the model like
// Studio_SeqAnims / Studio_SeqMovement / Studio_CPS read it: the blend grid, the two blend
// parameters (as merged pose parameter indices), their ranges or pose keys, and per animation of
// the grid its cycles per second and its linear motion over one cycle.
#define SM_G0       0
#define SM_G1       1
#define SM_P0       2
#define SM_P1       3
#define SM_PS0      4
#define SM_PS1      5
#define SM_PE0      6
#define SM_PE1      7
#define SM_KEYS     8
#define SM_KEY0     9
#define SM_KEY1     17
#define SM_MAXKEYS  8
#define SM_ANIM     25
#define SM_ASTRIDE  4                     // cps, motion x, y, z
#define SM_MAXANIMS 25
#define SM_SIZE     (SM_ANIM + SM_MAXANIMS * SM_ASTRIDE)
#define MAX_TRANSITIONS 3

#define TARGET_SURVIVOR  (1 << 0)
#define TARGET_SPECIAL   (1 << 1)
#define TARGET_COMMON    (1 << 2)
#define TARGET_OTHER     (1 << 3)

// studiohdr_t (MDL v44-v49)
#define STUDIO_ID            0x54534449
#define HDR_NUMPOSEPARAMS    300
#define HDR_POSEPARAMINDEX   304
#define HDR_NUMINCLUDES      336
#define HDR_INCLUDEINDEX     340
#define POSEDESC_SIZE        20
#define MODELGROUP_SIZE      8
#define HDR_NUMLOCALSEQ      188
#define HDR_LOCALSEQINDEX    192
#define SEQDESC_SIZE         212
#define SEQ_NAME_LEN         64

// CAnimationLayer: 76 bytes on Windows and Linux, m_AnimOverlay CUtlVector count at +12
// (layout comes from gamedata "CAnimationLayer::*"; these are the defaults)
int g_iLayerSize = 76, g_iLayerFlags = 0, g_iLayerSequence = 8, g_iLayerCycle = 12, g_iLayerPrevCycle = 16,
	g_iLayerWeight = 20, g_iLayerRate = 24, g_iLayerOrder = 60;
bool g_bLayersOK = true;
#define LAYER_SIZE       g_iLayerSize
#define LAYER_FLAGS      g_iLayerFlags
#define LAYER_SEQUENCE   g_iLayerSequence
#define LAYER_CYCLE      g_iLayerCycle
#define LAYER_PREVCYCLE  g_iLayerPrevCycle
#define LAYER_WEIGHT     g_iLayerWeight
#define LAYER_RATE       g_iLayerRate
#define LAYER_ORDER      g_iLayerOrder

public Plugin myinfo =
{
	name        = "[L4D2] Pose Parameter Lag Compensation",
	author      = "posesync",
	description = "Records and rewinds m_flPoseParameter together with the engine's lag compensation records",
	version     = PLUGIN_VERSION,
	url         = ""
};

ConVar g_cvEnable, g_cvTargets, g_cvDebug;

int g_iOffEyeAng = -1;     // CTerrorPlayer m_angEyeAngles[0] (m_angEyeAngles[1] follows)
bool  g_bAnimTarget[MAX_ENTS];
float g_fAnimTarget[MAX_ENTS];       // target time the animation frame is computed from (before the whole-tick position shift)
bool  g_bClockMain[MAX_ENTS];          // pre saved the present main sequence/cycle and computed the client clock ones
int   g_iClockSeq[MAX_ENTS];
float g_fClockCycle[MAX_ENTS];
bool  g_bSeqSaved[MAX_ENTS];
int   g_iSavedSeq[MAX_ENTS];
ConVar g_cvDraw;
#define DRAW_LIFE           4.0     // seconds the drawn hitboxes stay (the game's sv_showimpacts boxes stay 4 s too)
#define DRAW_BEAMS_PER_TICK 40      // a skeleton is about 200 beams; too many temp entities in one tick get dropped
#define DRAW_INTERVAL       0.5     // seconds between two drawn snapshots for the same shooter

// hitbox drawer (sm_posesync_drawhitboxes)
#define HB_BONE   0
#define HB_GROUP  1
#define HB_MINS   2
#define HB_MAXS   5
#define HB_SIZE   8
#define BEAM_SIZE 8          // start[3], end[3], color, userid
#define MAX_DRAW_BOXES 64
Handle g_hGetBoneAngles;
int    g_iLaser = -1;
ArrayList g_hBeams;
int    g_iBeamRead;                    // next beam to send (the queue is cleared once it is all sent)
#define MAX_QUEUED_BEAMS 2400          // about 2 s of sending; a new snapshot is skipped while the queue is fuller
int    g_iBeamTick = -1;
float  g_fNextDraw[MAXPLAYERS + 1];
float  g_fPingAllow[MAXPLAYERS + 1];   // last latency allowance the engine put into the target time, seconds
int    g_iPingReportTick[MAXPLAYERS + 1];
float  g_fLatestSim;                   // newest simulation time recorded on this map (the server's present)
int   g_iLastParity[MAX_ENTS];

// Member offsets, resolved once (inherited members have the same offset in every class), and a
// per-entity cache so the per-tick recording does no name lookups.
int g_iOffModelIndex = -1, g_iOffAbsOrigin = -1, g_iOffAbsRotation = -1, g_iOffSequence = -1, g_iOffCycle = -1, g_iOffRate = -1,
	g_iOffEffects = -1, g_iOffAbsVelocity = -1, g_iOffNoInterpParity = -1;
// CTerrorPlayer::m_mainSequenceStartTime: when the server last restarted a player's main sequence.
// The client restarts its own main sequence at cycle 0 when this changes (0x1027e760 -> 0x10145f10).
// anim_showstate prints it after the cycle; it is not a clock.
int g_iOffMainSeqStart = -1;
bool g_bBaseOffsets;
int  g_iCacheRef[MAX_ENTS];          // entity reference the cache below belongs to
bool g_bCacheHasPose[MAX_ENTS];
int  g_iCacheSeqStart[MAX_ENTS];     // m_sequenceStartTime offset (common infected / witch), -1 = none
int  g_iCacheOverlay[MAX_ENTS];      // m_AnimOverlay offset of this entity, -1 = not a CBaseAnimatingOverlay

// What each client was sent of each common infected / witch (SDKHook_SetTransmit), to follow
// client.dll's C_Infected frame rules: when a common comes into a client's view with a sequence
// start time the client does not have yet, the client sets the frame from the start time at the
// model's cycle rate, without the playback rate (0x10314784).
#define TX_GAP 0.2                    // seconds without a snapshot = the client's copy went dormant
#define PTX_MAX  33                     // client slots tracked per entity: L4D2 has at most 32 players
float g_fTxLast[PTX_MAX][MAX_ENTS];       // last time it was sent to that client
float g_fTxLastStart[PTX_MAX][MAX_ENTS];  // m_sequenceStartTime it had then
float g_fTxSeen[PTX_MAX][MAX_ENTS];       // when that m_sequenceStartTime was first sent to the client
float g_fTxEntry[PTX_MAX][MAX_ENTS];      // when it last came into view (moved on by repeated entries, below)
float g_fTxFirst[PTX_MAX][MAX_ENTS];      // first snapshot of that entry
// Newest tick_count the server has had from each client. Until the client's acknowledgement of the
// snapshot that brought a common into its view gets back to the server, every snapshot is a delta
// from an older acknowledged one that did not have the common, so it is sent again as entering the
// view. The client decodes it again from the baseline each time, which runs the start time proxies
// again and restarts the sequence and the overlays (seen live: 0 ms at net_fakelag 0, about 0.1 s
// at 50 and 0.2 s at 100 of restarts). Its tick_count is its clock, the snapshot time it has
// reached, so once one at or past the entry arrives the repeats stop.
int   g_iLastCmdTick[MAXPLAYERS + 1];
#define TX_REENTRY_MAX 1.0                      // stop treating snapshots as repeated entries after this long
float g_fTxEntryStart[PTX_MAX][MAX_ENTS]; // its m_sequenceStartTime at that moment
float g_fTxDormant[PTX_MAX][MAX_ENTS];    // when it last went out of view before that (the client's dormant time)
bool  g_bTxRecalc[PTX_MAX][MAX_ENTS];     // the start time was new to the client then
int   g_iTxStartOff[MAX_ENTS];                   // m_sequenceStartTime offset of a hooked entity
bool  g_bTxInf[MAX_ENTS];                        // a common or witch with transmit tracking (exists on clients it was sent to)

// Which server ticks each client was sent each player in (SDKHook_SetTransmit on players). A client
// only interpolates between the states it received: with cl_updaterate under the tick rate, or with
// choke, those are every few ticks, while the engine's records are every tick.
#define PTX_RING 128
int   g_iPlTx[PTX_MAX][PTX_MAX * PTX_RING];   // [receiver][player * PTX_RING + slot]
int   g_iPlTxHead[PTX_MAX][PTX_MAX];
int   g_iPlTxCount[PTX_MAX][PTX_MAX];
int   g_iPlTxEnter[PTX_MAX][PTX_MAX];   // [shooter][player]: tick the player entered the shooter's snapshots (after TX_GAP without one)
bool  g_bPlTxNew[PTX_MAX][PTX_MAX];     // [shooter][player]: that entry was the first since either connected (the client created the entity)
// Smallest gap seen between the tick count in a player's transmit hook and the tick of that player's
// newest lag compensation record (0 or 1 depending on where in the server frame each is read).
int   g_iTxRecGap = 1000;
int   g_iTxGapSamples;                  // times a gap of 1 was seen this map
// Per shooter and player: the restart delay of the current run, keyed by the run's
// m_mainSequenceStartTime (constant for the whole run), so it still applies once the run's first
// record has left the history.
int   g_iRlSeq[PTX_MAX][PTX_MAX];
int   g_iRlStartBits[PTX_MAX][PTX_MAX];
float g_fRlLag[PTX_MAX][PTX_MAX];
float g_fRlDelay[PTX_MAX][PTX_MAX];
// Overlay start times as each client got them. client.dll's m_flStartTime proxy for
// m_clientAnimatedOverlay (0x10313340): when a slot's start time changes, the client starts that
// overlay at its own clock of the moment, not at the server's start time, unless the common went
// dormant on it within the last second. Clients up to PTX_MAX only (the arrays are per slot).
// (entity and slot in one index, entity * MAX_CI_LAYERS + slot: a third dimension would add an index table
// of PTX_MAX * MAX_ENTS cells to the plugin file)
float g_fTxOvStart[PTX_MAX][MAX_ENTS * MAX_CI_LAYERS];   // start time last sent in that slot
float g_fTxOvSeen[PTX_MAX][MAX_ENTS * MAX_CI_LAYERS];    // when it was first sent
int   g_iTxOvVer[PTX_MAX][MAX_ENTS];                    // g_iOvVer the client's slots were last compared at
// The entity's overlay start times, read once per tick (the transmit hook runs once per client)
int   g_iOvTick[MAX_ENTS];
int   g_iOvVer[MAX_ENTS];                               // bumped when a start time changes
int   g_iOvCount[MAX_ENTS];
float g_fOvStart[MAX_ENTS * MAX_CI_LAYERS];   // entity * MAX_CI_LAYERS + slot
// C_Infected objects on a client (client.dll keeps every C_Infected in one list, 0x107ca60c); its
// count picks how the client sets a common's move blend (see ApplyCommonMove)
int   g_iInfCountTick[MAXPLAYERS + 1];
int   g_iInfCount[MAXPLAYERS + 1];
ConVar g_cvZSpeed;
bool  g_bInWindow[MAX_ENTS];                     // this rewind is inside a player's interpolation reset window
int   g_iStatClientPos, g_iStatMoveBlend, g_iStatCommonMove, g_iStatSpawnTurn;
bool  g_bEyeLocked;     // ApplyEyeDriven set the feet yaw from an eye lock
float g_fResetSim[MAXPLAYERS + 1];   // sim time of the player's newest REC_RESET record, -1 = none
int   g_iPlTxHooked[MAXPLAYERS + 1];             // userid the transmit hook was added for

// sm_posesync_debug: the lines of one lag compensation pass are held back and, at its end, only
// the ones about the entities the shot hit are printed (or, on a miss, the one the aim ray passed
// closest to)
ArrayList g_hDbgLines;
ArrayList g_hDbgEnts;
bool  g_bDbgPass;
int   g_iDbgAimEnt = -1;              // aim target taken at the end of the first rewind of the command
bool  g_bDbgAimHit;
bool  g_bDbgAimTaken;
bool  g_bDbgHit[MAX_ENTS];
bool  g_bDbgGunFired;                 // the running command fired a gun (weapon_fire, not a melee weapon or claw)
bool  g_bDbgEvents;                   // the debug-only game events are hooked
int   g_iDbgHitBox[MAX_ENTS];
int   g_iDbgHitGroup[MAX_ENTS];

// last CommonClientCycle call, for the debug report
int   g_iCcRule;                      // 0 = from the start time, 1 = came into view (older start), 2 = random start, 3 = came into view (start under 1 s ago: cycle 0 on arrival)
float g_fCcEntry, g_fCcPbr, g_fCcModelRate;
bool  g_bCcClamped;
int  g_iHistLen[MAX_ENTS];           // length of g_hHistory[ent] (avoids a native call per record)
float g_fHeadSim[MAX_ENTS];          // simulation time of the newest record (avoids an ArrayList read)
int   g_iHeadSeq[MAX_ENTS];          // sequence of the newest record
int   g_iHeadSeqStart[MAX_ENTS];     // its m_sequenceStartTime (bits), to see a sequence change without a new simulation time
int   g_iHeadCIHash[MAX_ENTS];       // and a hash of its m_clientAnimatedOverlay entries, for the same reason
bool  g_bCacheCI[MAX_ENTS];          // the entity has m_clientAnimatedOverlay (common infected, witch)
// Infected::m_clientAnimatedOverlay (CUtlVector of CInfectedAnimationLayer, 0x18 bytes: vtable,
// m_nSequence, m_flStartTime, m_nOrder, m_bLooping), from gamedata
int   g_iOffCIOverlay = -1;
#define CI_ELEM_SIZE 24
int   g_iStatIdleSeq;                // records added for such changes
bool g_bReclassify[MAX_ENTS];        // players: team may have changed, classify again at the next record

// clients that are in game and not bots (kept by OnClientPutInServer / OnClientDisconnect)
bool  g_bHuman[MAXPLAYERS + 1];

// sm_posesync_profile
Profiler g_hProf;
bool  g_bProfiling;
float g_fProfEnd;
float g_fProfRecord, g_fProfRewind;
int   g_iProfRecords, g_iProfTicks, g_iProfRewinds, g_iProfLastTick;
bool  g_bCycleSaved[MAX_ENTS];
float g_fSavedCycle[MAX_ENTS];
// what the plugin itself wrote this pass: at the restore, a value the game changed meanwhile (a death or
// stagger sequence, a new gesture in an overlay slot) is left alone
bool  g_bWroteSeq[MAX_ENTS], g_bWroteCycle[MAX_ENTS];
int   g_iWroteSeq[MAX_ENTS], g_iWroteCycleSeq[MAX_ENTS];
float g_fWroteCycle[MAX_ENTS];
bool  g_bTransSnap[MAX_ENTS];
int   g_iTransWritten[MAX_ENTS][16 * 7];          // slot * 7 + field, like g_iTransSaved
int   g_iAppliedModel[MAX_ENTS];      // model index when the entity was rewound (no restore onto another model)

// sm_posesync_trace
int   g_iTraceRef;
float g_fTraceEnd;
float g_fTraceLastSim;
int   g_iTraceLastParity = -1;
int   g_iTraceLastTick;


// player animstate (CTerrorPlayer::m_PlayerAnimState) fields, from gamedata
int  g_iOffAnimState = -1;    // CTerrorPlayer -> CTerrorPlayerAnimState*
int  g_iOffRenderYaw = -1;    // animstate m_angRender[YAW]: CBaseAnimating::SetupBones uses this for players, not the entity angles
int  g_iOffEyeYaw = -1, g_iOffGoalFeetYaw = -1, g_iOffFeetYaw = -1;
bool  g_bYawSaved[MAX_ENTS];
float g_fSavedYaw[MAX_ENTS];
Address g_aSavedAnim[MAX_ENTS];

// developer-only debug cvars that are hidden in retail builds
char g_sDevCvars[][] =
{
	"sv_showanimstate", "sv_showanimstate_log", "sv_showanimstate_activities",
	"cl_showanimstate", "cl_showanimstate_log", "cl_showanimstate_activities"
};

// overlay slots borrowed for client-side sequence transitions during a rewind
#define MAX_LAYERS_SAVED 16
int  g_iTransSaved[MAX_ENTS][MAX_LAYERS_SAVED * 7];  // per slot (slot * 7 + field): flags, seq, cycle, prevcycle, weight, rate, order
int  g_iTransCount[MAX_ENTS];                        // number of overlay slots saved (0 = nothing to undo)
int  g_iOffParity = -1;
ConVar g_cvMinRate, g_cvMaxRate, g_cvMinRatio, g_cvMaxRatio;
int  g_iShooter;              // client whose usercmd is running (the one being lag compensated for)
int  g_iPassShooter, g_iPassTick;   // whose command and which tick the current rewind pass started in
int  g_iOffLerpTime = -1;     // CBasePlayer::m_fLerpTime (gamedata)
ConVar g_cvMaxUnlag;

bool g_bEnabled;
int  g_iTargets, g_iDebug;

// Cvar values used on the hot paths, cached (reading a ConVar is a native call each time).
bool  g_bDraw;
float g_fTick = 0.0333333;           // server tick interval (constant while the server runs)
// Fixed client behaviour, measured in game:
// the client's clock is one tick ahead of the tick_count its command carries
#define CLIENT_CLOCK_TICKS 1
// seconds after a player's interpolation reset (a spawn, EF_NOINTERP) during which the client draws
// the newest position it has with a 0 speed estimate, counted in the time it draws (the target
// time): about its extrapolation limit (cl_extrapolate_amount, 0.25). Seen with anim_showstate at
// 100 tick: the estimate turned on 17 frames at 60 fps (about 0.28 s) after the client first had a
// spawned Jockey, at lerp 20 ms and at about 100 ms alike, which is 0.27 - 0.28 s of drawn time
// after the spawn record.
#define RESET_WINDOW_TIME 0.275
// record gaps over 64 units are bridged only when every gap is at most this fast (units/s); faster
// is a real teleport
#define SPARSE_MAX_SPEED 1000.0

Handle g_hInvalidateBoneCache;
Handle g_hMarkBoundsDirty;            // CCollisionProperty::MarkSurroundingBoundsDirty, optional
int    g_iOffCollision = -1;          // CBaseEntity::m_Collision
Handle g_hGetBoneOrigin;      // optional: debug aim target, debug 3 bone dump, hitbox drawer

#define NUM_DBG_BONES 9
char g_sDbgBones[NUM_DBG_BONES][] =
{
	"ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Head1",
	"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand",
	"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand",
	"ValveBiped.Bip01_L_Foot"
};

int g_iOffPose = -1;
int g_iOffSimTime = -1;

int g_iRingSize = 128;

// per-entity history ring
ArrayList g_hHistory[MAX_ENTS];
int  g_iHistRef[MAX_ENTS];
int  g_iHead[MAX_ENTS];
int  g_iCount[MAX_ENTS];
int  g_iClass[MAX_ENTS];

// per-entity "currently rewound" state
bool  g_bApplied[MAX_ENTS];
int   g_iAppliedRef[MAX_ENTS];
float g_fSaved[MAX_ENTS * MAXPOSE];          // entity * MAXPOSE + pose (one dimension: no index table in the plugin file)
int   g_iAppliedList[MAX_ENTS];
int   g_iAppliedCount;

// model info (pose ranges / loop) for wrap-aware interpolation and debug names
enum struct PoseModel
{
	bool valid;
	int numPose;
	char names[MAXPOSE * POSE_NAME_LEN];
	float start[MAXPOSE];
	float end[MAXPOSE];
	float loop[MAXPOSE];
	ArrayList seqNames;   // sequence labels in virtual-model order (index = sequence number)
	int dbgBone[NUM_DBG_BONES];
	ArrayList seqActs;    // per sequence: activity name (ACT_RUN, ...)
	ArrayList seqInfo;    // per sequence: SI_* block (flags, fade in/out, cycle rate)
	ArrayList hitboxes;   // hitbox set 0: HB_* block (bone, group, mins, maxs)
	int idxVert;
	int idxHoriz;
	ArrayList seqMoveIdx; // per sequence: row in seqMove, -1 = the sequence has no motion
	ArrayList seqMove;    // SM_* blocks
	int idxMoveX;
	int idxMoveY;
	int idxLeanYaw;
	int idxBodyYaw;
	int idxBodyPitch;
	int idxHeadYaw;
	int idxHeadPitch;
	int idxLeanPitch;
}
ArrayList g_Models;
StringMap g_ModelMap;
int g_iEntModelIndex[MAX_ENTS];
int g_iEntModelInfo[MAX_ENTS];

// stats
int g_iStatRecords, g_iStatBacktracks, g_iStatApplied, g_iStatNoHistory, g_iStatEngineRejected;

// Gaps in the engine's own lag compensation (each needs only its own gamedata entries)
//   swings:      CTerrorPlayer::WantsLagCompensationOnEntity only compensates while the command holds
//                attack / shove (or within 5 commands of a shove); melee swings, claws and the Tank's
//                punch keep testing for hits after the button is released.
//   ridden:      a Jockey riding a survivor is parented to that survivor and never compensated; the
//                ridden survivor is compensated instead, which carries the Jockey with it.
//   animrewind:  FireTerrorBullets starts lag compensation along a ray from the world origin with
//                range 0, so BacktrackEntity skips the sequence / cycle / layer rewind for gunshots.
//   sparse:      BacktrackEntity refuses entities whose records are more than 64 units apart.
#define CLIENT_PLAYER_VIEW_Z 62.0           // CTerrorGameRules view vectors m_vView: the view offset C_TerrorPlayer gives other players
bool  g_bHaveWants, g_bHaveStart;
Handle g_hSetAbsOrigin, g_hSetAbsAngles;   // optional: the sparse record bridge and the common hold
bool  g_bCanMove;                          // both of them were found
#define CMD_COMMAND_NUMBER 4                // CUserCmd (vtable first)
#define CMD_BUTTONS        36
#define LAGCOMP_HITBOXES          1
#define LAGCOMP_HITBOXES_ALONG_RAY 2
int  g_iOffLastMeleeCmd = -1;               // CTerrorPlayer: command number of the last shove (gamedata)
int  g_iOffActiveWeapon = -1, g_iOffInMeleeSwing = -1, g_iOffSwingTimer = -1;
int  g_iOffJockeyAttacker = -1, g_iOffCarryVictim = -1;
bool g_bButtonsPatched;
int  g_iPatchedButtons;
Address g_aPatchedCmd;                      // the CUserCmd whose buttons the pre hook changed
int  g_iPatchedShooter, g_iPatchedTick;     // whose command and when (the pointer is only good during it)
// players moved by their parent's rewind (Jockey on a rewound survivor, survivor carried by a rewound
// Charger): their bone cache is flushed after the rewind and again after FinishLagCompensation
int  g_iFollowers[MAXPLAYERS + 1];
int  g_iFollowerCount;
// sparse record bridge: present origin / angles to put back
bool  g_bSparseMoved[MAX_ENTS];
float g_fSparseOrg[MAX_ENTS * 3];            // entity * 3 + axis, like the other per-entity vectors
float g_fSparseAng[MAX_ENTS * 3];
float g_fSparseTo[MAX_ENTS * 3];             // where it was moved to
// CBaseEntity::SetAbsOrigin / SetAbsAngles set m_flSimulationTime to the current time whenever they
// change something (server 0x5fc85c). The plugin's own moves must not leave that behind: the client
// would take it as a new position sample, stamped now, of a common that last moved on its previous
// NextBot update, and draw the common stopping there and catching up (a jitter on every shot).
float g_fSparseSim[MAX_ENTS];
float g_fHeldSim[MAX_ENTS];
// common hold: the engine's rewound origin / angles of a common held at the client's newest update
bool  g_bHeld[MAX_ENTS];
float g_fHeldEngOrg[MAX_ENTS * 3];
float g_fHeldEngAng[MAX_ENTS * 3];
int   g_iStatHold;
int g_iStatSwing, g_iStatRidden, g_iStatAnimRewind, g_iStatSparse;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "This plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_fTick = GetTickInterval();
	CreateConVar("l4d2_posesync_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	// on / off and debugging
	g_cvEnable  = CreateConVar("sm_posesync_enable",  "1",  "1 = make the lag compensated hitboxes match what the shooter's client drew.", _, true, 0.0, true, 1.0);
	g_cvTargets = CreateConVar("sm_posesync_targets", "15", "Bitmask: 1 = survivors, 2 = special infected, 4 = common infected + witch, 8 = any other lag compensated entity.", _, true, 0.0, true, 15.0);
	g_cvDebug   = CreateConVar("sm_posesync_debug",   "0",  "1 = per lag compensated command, print how the entity that was hit (for a gun shot that misses, the one the aim ray passed closest to; a shove, melee swing or claw that hits nothing prints nothing) was rewound, 2 = also every pose parameter that changed, 3 = also the full server animation state the hitboxes were built from.", _, true, 0.0, true, 3.0);

	// hitbox drawer
	g_cvDraw = CreateConVar("sm_posesync_drawhitboxes", "0", "1 = when you shoot, shove or swing, draw the server's lag compensated hitboxes (after this plugin's corrections) of the entity your aim ray hits, or the one closest to it, as beams only you can see. Works on a dedicated server, where sv_showimpacts boxes are never sent. Box hit by the aim ray: yellow, other boxes: green, missed entity: white.", _, true, 0.0, true, 1.0);

	g_cvZSpeed   = FindConVar("z_speed");
	g_cvMinRate  = FindConVar("sv_minupdaterate");
	g_cvMaxRate  = FindConVar("sv_maxupdaterate");
	g_cvMinRatio = FindConVar("sv_client_min_interp_ratio");
	g_cvMaxRatio = FindConVar("sv_client_max_interp_ratio");
	g_cvEnable.AddChangeHook(OnCvarChanged);
	g_cvTargets.AddChangeHook(OnCvarChanged);
	g_cvDebug.AddChangeHook(OnCvarChanged);
	g_cvDraw.AddChangeHook(OnCvarChanged);

	g_cvMaxUnlag = FindConVar("sv_maxunlag");
	if (g_cvMaxUnlag != null)
		g_cvMaxUnlag.AddChangeHook(OnMaxUnlagChanged);

	AutoExecConfig(true, "l4d2_posesync");

	RegAdminCmd("sm_posesync_status", Cmd_Status, ADMFLAG_ROOT, "Show pose lag compensation stats.");
	RegAdminCmd("sm_posesync_dump", Cmd_Dump, ADMFLAG_ROOT, "sm_posesync_dump <entindex> - print the entity's current server animation state.");
	RegAdminCmd("sm_posesync_trace", Cmd_Trace, ADMFLAG_ROOT, "sm_posesync_trace <entindex> [seconds] - print the entity's simulation time, origin, velocity, no-interp state, sequence, cycle and body yaw every server tick.");
	RegAdminCmd("sm_posesync_profile", Cmd_Profile, ADMFLAG_ROOT, "sm_posesync_profile [seconds] - measure the plugin's own CPU time (recording every tick, rewinding per shot) and print it.");
	RegAdminCmd("sm_posesync_unhide", Cmd_Unhide, ADMFLAG_ROOT, "Unhide the developer-only animstate debug cvars (sv_showanimstate, sv_showanimstate_log, cl_showanimstate_log, ...).");
	RegAdminCmd("sm_posesync_history", Cmd_History, ADMFLAG_ROOT, "sm_posesync_history <entindex> [records] - dump stored pose history of an entity.");

	g_Models = new ArrayList(sizeof(PoseModel));
	g_hBeams = new ArrayList(BEAM_SIZE);
	g_ModelMap = new StringMap();
	for (int i = 0; i < MAX_ENTS; i++)
	{
		g_iEntModelIndex[i] = -1;
		g_iEntModelInfo[i] = -1;
	}

	SetupHooks();
	ReadCvars();
	UpdateRingSize();

	HookEvent("player_spawn", Event_PlayerReset);
	HookEvent("player_death", Event_PlayerReset);
	HookEvent("player_team", Event_PlayerTeam);
}

// Detours on the engine's lag compensation manager, SDK calls and the platform-dependent offsets,
// all from the gamedata. Missing optional pieces turn off only the feature that needs them.
void SetupHooks()
{
	GameData gd = new GameData(GAMEDATA);
	if (gd == null)
		SetFailState("Missing gamedata/%s.txt", GAMEDATA);

	DynamicDetour dRecord = DynamicDetour.FromConf(gd, "CLagCompensationManager::RecordDataIntoTrack");
	DynamicDetour dBacktrack = DynamicDetour.FromConf(gd, "CLagCompensationManager::BacktrackEntity");
	DynamicDetour dFinish = DynamicDetour.FromConf(gd, "CLagCompensationManager::FinishLagCompensation");
	if (dRecord == null || dBacktrack == null || dFinish == null)
		SetFailState("Could not create detours for%s%s%s (signature not found in the server binary, or entry missing in %s.txt).",
			dRecord == null ? " RecordDataIntoTrack" : "", dBacktrack == null ? " BacktrackEntity" : "",
			dFinish == null ? " FinishLagCompensation" : "", GAMEDATA);

	if (!dRecord.Enable(Hook_Post, Detour_Record_Post))
		SetFailState("Failed to detour CLagCompensationManager::RecordDataIntoTrack");
	if (!dBacktrack.Enable(Hook_Pre, Detour_Backtrack_Pre) || !dBacktrack.Enable(Hook_Post, Detour_Backtrack_Post))
		SetFailState("Failed to detour CLagCompensationManager::BacktrackEntity");
	if (!dFinish.Enable(Hook_Pre, Detour_Finish_Pre) || !dFinish.Enable(Hook_Post, Detour_Finish_Post))
		SetFailState("Failed to detour CLagCompensationManager::FinishLagCompensation");

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CBaseAnimating::InvalidateBoneCache"))
		SetFailState("Signature CBaseAnimating::InvalidateBoneCache not found");
	g_hInvalidateBoneCache = EndPrepSDKCall();
	if (g_hInvalidateBoneCache == null)
		SetFailState("Could not prepare SDKCall CBaseAnimating::InvalidateBoneCache");

	StartPrepSDKCall(SDKCall_Raw);
	if (PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CCollisionProperty::MarkSurroundingBoundsDirty"))
		g_hMarkBoundsDirty = EndPrepSDKCall();
	if (g_hMarkBoundsDirty == null)
		LogError("CCollisionProperty::MarkSurroundingBoundsDirty not found: shots can miss when the client's animation is not the engine's one");

	g_iOffLerpTime = gd.GetOffset("CBasePlayer::m_fLerpTime");

	// CAnimationLayer layout (overlay layers): all eight must be present for the platform,
	// otherwise the layer features (crossfade, client clock layers) are switched off.
	{
		static const char names[8][] = { "size", "m_fFlags", "m_nSequence", "m_flCycle", "m_flPrevCycle", "m_flWeight", "m_flPlaybackRate", "m_nOrder" };
		int v[8];
		g_bLayersOK = true;
		for (int i = 0; i < 8; i++)
		{
			char key[64];
			FormatEx(key, sizeof(key), "CAnimationLayer::%s", names[i]);
			v[i] = gd.GetOffset(key);
			if (v[i] < 0)
				g_bLayersOK = false;
		}
		if (g_bLayersOK)
		{
			g_iLayerSize = v[0]; g_iLayerFlags = v[1]; g_iLayerSequence = v[2]; g_iLayerCycle = v[3];
			g_iLayerPrevCycle = v[4]; g_iLayerWeight = v[5]; g_iLayerRate = v[6]; g_iLayerOrder = v[7];
		}
		else
			LogError("CAnimationLayer offsets missing from gamedata for this platform: sequence crossfade and client clock layers are off.");
	}
	g_iOffAnimState = gd.GetOffset("CTerrorPlayer::m_PlayerAnimState");
	int render = gd.GetOffset("CTerrorPlayerAnimState::m_angRender");
	g_iOffRenderYaw = (render != -1) ? render + 4 : -1;
	g_iOffEyeYaw = gd.GetOffset("CTerrorPlayerAnimState::m_flEyeYaw");
	g_iOffGoalFeetYaw = gd.GetOffset("CTerrorPlayerAnimState::m_flGoalFeetYaw");
	g_iOffFeetYaw = gd.GetOffset("CTerrorPlayerAnimState::m_flCurrentFeetYaw");
	if (g_iOffAnimState == -1 || g_iOffRenderYaw == -1)
		LogError("Animstate offsets missing from gamedata, body yaw will not be rewound.");


	g_hGetBoneOrigin = PrepEntityCall(gd, "CBaseAnimating::ScriptGetBoneOrigin", SDKType_PlainOldData, SDKPass_Plain, true, SDKType_Vector);
	g_hGetBoneAngles = PrepEntityCall(gd, "CBaseAnimating::ScriptGetBoneAngles", SDKType_PlainOldData, SDKPass_Plain, true, SDKType_QAngle);
	if (g_hGetBoneOrigin == null || g_hGetBoneAngles == null)
		LogError("ScriptGetBoneOrigin/ScriptGetBoneAngles not found, sm_posesync_drawhitboxes will not work.");

	// Gaps in the engine's lag compensation. Each one only needs its own entries.
	DynamicDetour dWants = DynamicDetour.FromConf(gd, "CTerrorPlayer::WantsLagCompensationOnEntity");
	if (dWants != null && dWants.Enable(Hook_Pre, Detour_Wants_Pre))
	{
		if (dWants.Enable(Hook_Post, Detour_Wants_Post))
			g_bHaveWants = true;
		else
			dWants.Disable(Hook_Pre, Detour_Wants_Pre);   // never change the buttons without putting them back
	}
	if (!g_bHaveWants)
		LogError("CTerrorPlayer::WantsLagCompensationOnEntity not found: swings and Jockey-ridden survivors are not compensated beyond what the game does.");
	g_iOffLastMeleeCmd = gd.GetOffset("CTerrorPlayer::m_iLastShoveCommand");

	DynamicDetour dStart = DynamicDetour.FromConf(gd, "CLagCompensationManager::StartLagCompensation");
	if (dStart != null && dStart.Enable(Hook_Pre, Detour_Start_Pre))
		g_bHaveStart = true;
	else
		LogError("CLagCompensationManager::StartLagCompensation not found: the animation rewind for gunshots is off.");

	g_hSetAbsOrigin = PrepEntityCall(gd, "CBaseEntity::SetAbsOrigin", SDKType_Vector, SDKPass_ByRef);
	g_hSetAbsAngles = PrepEntityCall(gd, "CBaseEntity::SetAbsAngles", SDKType_QAngle, SDKPass_ByRef);
	g_bCanMove = g_hSetAbsOrigin != null && g_hSetAbsAngles != null;
	if (!g_bCanMove)
		LogError("CBaseEntity::SetAbsOrigin/SetAbsAngles not found: the sparse record bridge and the common hold are off.");

	// common infected overlay list; sanity check: it follows m_clientLeanYaw on both platforms
	g_iOffCIOverlay = gd.GetOffset("Infected::m_clientAnimatedOverlay");
	int lean = FindSendPropInfo("Infected", "m_clientLeanYaw");
	if (g_iOffCIOverlay > 0 && lean > 0 && g_iOffCIOverlay != lean + 4)
	{
		LogError("Infected::m_clientAnimatedOverlay offset %d does not follow m_clientLeanYaw (%d): common infected overlay layers are off.", g_iOffCIOverlay, lean);
		g_iOffCIOverlay = -1;
	}

	g_iOffActiveWeapon = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon");
	g_iOffInMeleeSwing = FindSendPropInfo("CTerrorMeleeWeapon", "m_bInMeleeSwing");
	g_iOffSwingTimer = FindSendPropInfo("CTerrorWeapon", "m_swingTimer");
	g_iOffJockeyAttacker = FindSendPropInfo("CTerrorPlayer", "m_jockeyAttacker");
	g_iOffCarryVictim = FindSendPropInfo("CTerrorPlayer", "m_carryVictim");

	delete gd;
}

// An optional SDKCall on an entity with one parameter (and a by-value return when hasRet); null
// when the signature is missing.
Handle PrepEntityCall(GameData gd, const char[] name, SDKType param, SDKPassMethod pass, bool hasRet = false, SDKType ret = SDKType_Vector)
{
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gd, SDKConf_Signature, name))
	{
		EndPrepSDKCall();
		return null;
	}
	PrepSDKCall_AddParameter(param, pass);
	if (hasRet)
		PrepSDKCall_SetReturnInfo(ret, SDKPass_ByValue);
	return EndPrepSDKCall();
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ReadCvars();
}

void ReadCvars()
{
	bool wasEnabled = g_bEnabled;
	int oldTargets = g_iTargets;
	g_bEnabled = g_cvEnable.BoolValue;
	g_iTargets = g_cvTargets.IntValue;
	g_iDebug   = g_cvDebug.IntValue;
	g_bDraw    = g_cvDraw.BoolValue;

	if (wasEnabled && !g_bEnabled)
		RestoreAll();
	// recording stopped while off (or for a class that was taken out): those histories end minutes
	// ago, and must not be interpolated against new records
	else if ((!wasEnabled && g_bEnabled) || (g_bEnabled && g_iTargets != oldTargets))
		ClearAllHistory();

	// game events the debug filter uses, hooked only while sm_posesync_debug is on
	bool want = g_iDebug > 0;
	if (want != g_bDbgEvents)
	{
		g_bDbgEvents = want;
		static const char evs[][] = { "weapon_fire", "entity_shoved", "player_shoved", "infected_hurt", "player_hurt" };
		static bool hooked[sizeof(evs)];
		for (int i = 0; i < sizeof(evs); i++)
		{
			if (want && !hooked[i])
				hooked[i] = HookEventEx(evs[i], Event_DbgCommand);
			else if (!want && hooked[i])
			{
				UnhookEvent(evs[i], Event_DbgCommand);
				hooked[i] = false;
			}
		}
	}
}

public void OnMaxUnlagChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	UpdateRingSize();
}

public void OnMapStart()
{
	g_fTick = GetTickInterval();
	g_iLaser = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	if (g_hBeams != null)
		g_hBeams.Clear();
	g_iBeamRead = 0;
	// the tick count starts again on a new map
	for (int c = 0; c <= MaxClients; c++)
	{
		g_fNextDraw[c] = 0.0;
		g_iLastCmdTick[c] = 0;
		g_iInfCountTick[c] = -1;
		for (int p = 0; p < PTX_MAX && c < PTX_MAX; p++)
			g_iPlTxCount[c][p] = 0;
	}
	g_fLatestSim = 0.0;
	g_iTxRecGap = 1000;
	g_iTxGapSamples = 0;
	UpdateRingSize();
	ClearAllHistory();
	for (int i = 0; i < MAX_ENTS; i++)
	{
		g_iEntModelIndex[i] = -1;
		g_iEntModelInfo[i] = -1;
	}
}

// late load: hook the commons and witches that already exist
void HookExistingInfected()
{
	for (int c = 1; c <= MaxClients; c++)
	{
		if (IsClientInGame(c))
		{
			SDKHook(c, SDKHook_TraceAttack, Hook_TraceAttack);
			g_bHuman[c] = !IsFakeClient(c);
			RequestFrame(Frame_PrimeModel, EntIndexToEntRef(c));
		}
	}
	char cls[16];
	for (int e = MaxClients + 1; e < MAX_ENTS; e++)
	{
		if (!IsValidEntity(e))
			continue;
		GetEntityClassname(e, cls, sizeof(cls));
		if (StrEqual(cls, "infected") || StrEqual(cls, "witch"))
		{
			HookTransmit(e, cls, true);
			RequestFrame(Frame_PrimeModel, EntIndexToEntRef(e));
		}
	}
}

public void OnAllPluginsLoaded()
{
	HookExistingInfected();
	// late load: players already in game
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_iPlTxHooked[i] != GetClientUserId(i))
			OnClientPutInServer(i);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_TraceAttack, Hook_TraceAttack);
	SDKHook(client, SDKHook_SetTransmit, Hook_PlayerTransmit);
	g_iPlTxHooked[client] = GetClientUserId(client);
	g_bHuman[client] = !IsFakeClient(client);
	for (int c = 0; c < PTX_MAX && client < PTX_MAX; c++)
	{
		g_iPlTxCount[c][client] = 0;    // client as the player that is sent
		g_iPlTxCount[client][c] = 0;    // client as the receiver
		g_iRlSeq[c][client] = -1;
		g_iRlSeq[client][c] = -1;
	}
	g_iInfCountTick[client] = -1;
	g_iLastCmdTick[client] = 0;
	g_fResetSim[client] = -1.0;
	for (int e = MaxClients + 1; e < MAX_ENTS && client < PTX_MAX; e++)
	{
		g_fTxLast[client][e] = -1000.0;
		g_fTxLastStart[client][e] = -1.0;
		g_fTxSeen[client][e] = -1000.0;
		g_fTxEntry[client][e] = -1000.0;
		g_fTxFirst[client][e] = -1000.0;
		g_bTxRecalc[client][e] = false;
		g_fTxDormant[client][e] = -1000.0;
		g_iTxOvVer[client][e] = -1;
		for (int k = 0; k < MAX_CI_LAYERS; k++)
		{
			g_fTxOvStart[client][e * MAX_CI_LAYERS + k] = -1.0;
			g_fTxOvSeen[client][e * MAX_CI_LAYERS + k] = -1000.0;
		}
	}
}

public void OnPluginEnd()
{
	UndoButtonPatch(g_iShooter);
	RestoreAll();
	ReleaseFollowers();
}

public void OnConfigsExecuted()
{
	UnhideDevCvars(false);
}

// History length: enough records to cover sv_maxunlag (the furthest the engine rewinds), plus a margin.
void UpdateRingSize()
{
	float maxUnlag = (g_cvMaxUnlag != null) ? g_cvMaxUnlag.FloatValue : 1.0;
	float interval = g_fTick;
	int size = RoundToCeil(maxUnlag / interval) + 8;
	if (size < 16) size = 16;
	if (size > MAX_RING) size = MAX_RING;

	if (size != g_iRingSize)
	{
		g_iRingSize = size;
		ClearAllHistory();
	}
}

void ClearAllHistory()
{
	RestoreAll();
	for (int i = 0; i < MAX_ENTS; i++)
		DeleteHistory(i);
}

void DeleteHistory(int ent)
{
	g_iCacheRef[ent] = 0;
	delete g_hHistory[ent];
	g_iHistRef[ent] = 0;
	g_iHead[ent] = 0;
	g_iCount[ent] = 0;
}

// ---------------------------------------------------------------------------
// Debug output (sm_posesync_debug)
//
// A lag compensated command rewinds every entity near the shooter. Printing all of them would bury
// the one that matters, so the lines are held back during the command and only those about the
// entities the bullets hit (or, on a miss, the one the aim ray passed closest to) are printed at its
// end. Lines with entity 0 are about the whole command and are always printed.
// ---------------------------------------------------------------------------

// Print, or hold back while a command is being lag compensated.
void Dbg(int entity, const char[] fmt, any ...)
{
	char buf[768];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (g_bDbgPass && g_hDbgLines != null)
	{
		g_hDbgLines.PushString(buf);
		g_hDbgEnts.Push(entity);
	}
	else
		PrintToServer("%s", buf);
}

// Start holding back debug lines (first rewind of a command).
void DbgBeginPass()
{
	if (g_bDbgPass || g_iDebug <= 0)
		return;
	if (g_hDbgLines == null)
	{
		g_hDbgLines = new ArrayList(ByteCountToCells(768));
		g_hDbgEnts = new ArrayList();
	}
	g_hDbgLines.Clear();
	g_hDbgEnts.Clear();
	for (int i = 0; i < MAX_ENTS; i++)
		g_bDbgHit[i] = false;
	g_iDbgAimEnt = -1;
	g_bDbgAimHit = false;
	g_bDbgAimTaken = false;
	g_bDbgPass = true;
}

// end of the pass (everything is still rewound): print the lines of the entities that were shot
void DbgEndPass(int shooter)
{
	if (!g_bDbgPass)
		return;
	g_bDbgPass = false;
	if (g_hDbgLines == null || g_hDbgLines.Length == 0)
		return;

	bool any = false;
	for (int i = 0; i < g_iAppliedCount; i++)
		if (g_bDbgHit[g_iAppliedList[i]])
			any = true;
	for (int i = 0; i < g_hDbgEnts.Length; i++)
	{
		int e = g_hDbgEnts.Get(i);
		if (e > 0 && g_bDbgHit[e])
			any = true;
	}
	int aimEnt = g_iDbgAimEnt;
	bool aimHit = g_bDbgAimHit;

	// a rewind outside a player command (another plugin's lag compensation): no shot to filter by
	if (shooter <= 0)
	{
		char line[768];
		for (int i = 0; i < g_hDbgLines.Length; i++)
		{
			g_hDbgLines.GetString(i, line, sizeof(line));
			PrintToServer("%s", line);
		}
		PrintToServer("[posesync] (lag compensation outside a player command)");
		g_hDbgLines.Clear();
		g_hDbgEnts.Clear();
		return;
	}

	// a player's shove, melee swing or claw that hit nothing: nothing worth printing
	if (!any && !g_bDbgGunFired)
	{
		g_hDbgLines.Clear();
		g_hDbgEnts.Clear();
		return;
	}

	char buf[768];
	int shown = 0;
	for (int i = 0; i < g_hDbgLines.Length; i++)
	{
		int e = g_hDbgEnts.Get(i);
		if (e == 0 || (any ? g_bDbgHit[e] : e == aimEnt))
		{
			g_hDbgLines.GetString(i, buf, sizeof(buf));
			PrintToServer("%s", buf);
			if (e != 0)
				shown++;
		}
	}
	if (any)
	{
		for (int e = 1; e < MAX_ENTS; e++)
		{
			if (!g_bDbgHit[e])
				continue;
			if (g_iDbgHitBox[e] == -2)
				PrintToServer("[posesync] this command shoved ent %d", e);
			else if (g_iDbgHitBox[e] == -1)
				PrintToServer("[posesync] this command hit ent %d (group %d)", e, g_iDbgHitGroup[e]);
			else
				PrintToServer("[posesync] this command hit ent %d, hitbox %d (group %d)", e, g_iDbgHitBox[e], g_iDbgHitGroup[e]);
		}
	}
	else if (aimEnt != -1)
		PrintToServer("[posesync] this shot hit nothing that is lag compensated (a miss or bullet spread); shown: ent %d, %s", aimEnt,
			aimHit ? "the server hitboxes your aim ray goes through" : "the one your aim ray passes closest to");
	else
		PrintToServer("[posesync] this shot hit nothing that is lag compensated, and no rewound entity was near your aim");
	g_hDbgLines.Clear();
	g_hDbgEnts.Clear();
}

// end of a rewind (still rewound): remember what the aim ray goes through, for a shot that hits
// nothing. The lines are printed when the whole command has run (OnPlayerRunCmdPost), because the
// game can apply bullet hits after it has put the entities back.
void DbgTakeAim(int shooter)
{
	if (!g_bDbgPass || g_bDbgAimTaken || shooter <= 0 || shooter > MaxClients || !IsClientInGame(shooter))
		return;
	int aimBox;
	float aimT, aimMiss;
	FindAimTarget(shooter, g_iDbgAimEnt, aimBox, aimT, aimMiss, g_bDbgAimHit);
	g_bDbgAimTaken = true;
}

// Debug filter: what the running command did. weapon_fire tells a gun shot from a shove, a melee
// swing or a claw; the shove events and the hurt events catch hits that do not go through
// TraceAttack (shoves never do). A command that fired no gun and hit nothing prints nothing.
void Event_DbgCommand(Event event, const char[] name, bool dontBroadcast)
{
	int shooter = g_iShooter;
	if (shooter <= 0 || g_iDebug <= 0)
		return;
	if (StrEqual(name, "weapon_fire"))
	{
		if (GetClientOfUserId(event.GetInt("userid")) != shooter)
			return;
		char weapon[32];
		event.GetString("weapon", weapon, sizeof(weapon));
		if (StrContains(weapon, "melee") == -1 && StrContains(weapon, "chainsaw") == -1 && StrContains(weapon, "claw") == -1)
			g_bDbgGunFired = true;
		return;
	}
	if (!g_bDbgPass || GetClientOfUserId(event.GetInt("attacker")) != shooter)
		return;
	int victim = StrEqual(name, "entity_shoved") || StrEqual(name, "infected_hurt") ? event.GetInt("entityid")
		: GetClientOfUserId(event.GetInt("userid"));
	if (victim <= 0 || victim >= MAX_ENTS)
		return;
	bool shove = StrEqual(name, "entity_shoved") || StrEqual(name, "player_shoved");
	if (shove)
	{
		g_iDbgHitBox[victim] = -2;          // shoved
		g_iDbgHitGroup[victim] = -1;
	}
	else if (!g_bDbgHit[victim])
	{
		g_iDbgHitBox[victim] = -1;          // hurt, hitbox unknown
		g_iDbgHitGroup[victim] = event.GetInt("hitgroup");
	}
	g_bDbgHit[victim] = true;
}

// Notes which entity and hitbox the shooter's bullets hit during the command, for the debug filter.
public Action Hook_TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (g_bDbgPass && victim > 0 && victim < MAX_ENTS && attacker == g_iShooter)
	{
		if (!g_bDbgHit[victim])
		{
			g_iDbgHitBox[victim] = hitbox;
			g_iDbgHitGroup[victim] = hitgroup;
		}
		g_bDbgHit[victim] = true;
	}
	return Plugin_Continue;
}

// ---------------------------------------------------------------------------
// Visibility tracking for common infected and witches
//
// client.dll sets a common's animation frame differently depending on whether it saw the current
// sequence start or the common came into view after it started (see CommonClientCycle). The plugin
// follows when each common was sent to each client to know which case applies to the shooter.
// ---------------------------------------------------------------------------

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity <= MaxClients || entity >= MAX_ENTS)
		return;
	if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
	{
		HookTransmit(entity, classname);
		RequestFrame(Frame_PrimeModel, EntIndexToEntRef(entity));
	}
}

// Reads the entity's model file now (the next frame, once the model is set) instead of during the
// first shot at it: parsing a model with hundreds of sequences inside a lag compensation pass would
// stall that player's command.
void Frame_PrimeModel(int ref)
{
	int entity = EntRefToEntIndex(ref);
	if (entity <= 0 || entity >= MAX_ENTS || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Data, "m_flPoseParameter"))
		return;
	PoseModel pm;
	GetPoseModel(entity, pm);
}

// Hooks one common or witch: transmit tracking and hit detection for the debug filter.
// existing: the entity was already there when the plugin loaded. Clients may have it in view with its
// current start time already, so it is not treated as coming into view at the first transmit.
void HookTransmit(int entity, const char[] classname, bool existing = false)
{
	g_iTxStartOff[entity] = FindSendPropInfo(StrEqual(classname, "witch") ? "Witch" : "Infected", "m_sequenceStartTime");
	float now = GetGameTime();
	float start = (existing && g_iTxStartOff[entity] > 0) ? GetEntDataFloat(entity, g_iTxStartOff[entity]) : -1.0;
	g_iOvTick[entity] = -1;
	g_iOvCount[entity] = 0;
	g_iOvVer[entity]++;
	for (int c = 0; c <= MaxClients && c < PTX_MAX; c++)
	{
		g_fTxLast[c][entity] = existing ? now : -1000.0;
		g_fTxLastStart[c][entity] = start;
		g_fTxSeen[c][entity] = -1000.0;
		g_fTxEntry[c][entity] = -1000.0;
		g_fTxFirst[c][entity] = -1000.0;
		g_fTxEntryStart[c][entity] = -1.0;
		g_fTxDormant[c][entity] = -1000.0;
		g_bTxRecalc[c][entity] = false;
		g_iTxOvVer[c][entity] = -1;
		for (int k = 0; k < MAX_CI_LAYERS; k++)
		{
			g_fTxOvStart[c][entity * MAX_CI_LAYERS + k] = -1.0;
			g_fTxOvSeen[c][entity * MAX_CI_LAYERS + k] = -1000.0;
		}
	}
	g_bTxInf[entity] = true;
	if (g_iTxStartOff[entity] > 0)
		SDKHook(entity, SDKHook_SetTransmit, Hook_Transmit);
	SDKHook(entity, SDKHook_TraceAttack, Hook_TraceAttack);
}

// called for each client the entity is about to be sent to (it is in that client's PVS)
public Action Hook_Transmit(int entity, int client)
{
	// only human shooters use this (a bot's lag compensation has no client drawing anything)
	if (client < 1 || client >= PTX_MAX || !g_bHuman[client])
		return Plugin_Continue;
	float now = GetGameTime();
	float start = GetEntDataFloat(entity, g_iTxStartOff[entity]);
	if (now - g_fTxLast[client][entity] > TX_GAP)
	{
		// coming back into view: the client recomputes the frame only if the start time is new to it
		g_fTxEntry[client][entity] = now;
		g_fTxFirst[client][entity] = now;
		g_fTxEntryStart[client][entity] = start;
		g_fTxDormant[client][entity] = g_fTxLast[client][entity];   // last snapshot before the gap
		g_bTxRecalc[client][entity] = (start != g_fTxLastStart[client][entity]);
	}
	else if (g_bTxRecalc[client][entity] && now - g_fTxFirst[client][entity] < TX_REENTRY_MAX
		&& float(g_iLastCmdTick[client]) * g_fTick < g_fTxFirst[client][entity] - 0.5 * g_fTick)
	{
		// the client has not confirmed the entry yet: this snapshot enters it again, and the client
		// starts the sequence and the overlays over when it gets it
		g_fTxEntry[client][entity] = now;
		g_fTxEntryStart[client][entity] = start;
		g_fTxSeen[client][entity] = now;
		if (g_bCacheCI[entity])
			TrackOverlayStarts(entity, client, now, true);
	}
	if (start != g_fTxLastStart[client][entity])
		g_fTxSeen[client][entity] = now;     // first snapshot with this start time
	if (g_bCacheCI[entity])
		TrackOverlayStarts(entity, client, now);
	g_fTxLast[client][entity] = now;
	g_fTxLastStart[client][entity] = start;
	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity)
{
	if (entity > 0 && entity < MAX_ENTS)
	{
		g_bTxInf[entity] = false;
		if (g_bApplied[entity])
			RemoveFromAppliedList(entity);
		ClearRewindState(entity);
		DeleteHistory(entity);
		g_iEntModelIndex[entity] = -1;
		g_iEntModelInfo[entity] = -1;
	}
}

public void OnClientDisconnect(int client)
{
	g_bHuman[client] = false;
	if (g_bApplied[client])
		RemoveFromAppliedList(client);
	ClearRewindState(client);
	DeleteHistory(client);
	g_iEntModelIndex[client] = -1;
	g_iEntModelInfo[client] = -1;
}

// A team change: classify the player again at its next record (sm_posesync_targets).
void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
		g_bReclassify[client] = true;
}

void Event_PlayerReset(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		// New life (or new SI class model): old poses must never be rewound into it.
		g_iCount[client] = 0;
		g_fResetSim[client] = -1.0;
		g_iHead[client] = 0;
		if (StrEqual(name, "player_spawn"))
			RequestFrame(Frame_PrimeModel, EntIndexToEntRef(client));
	}
}

// ---------------------------------------------------------------------------
// Recording
//
// The engine adds a lag record for an entity whenever its simulation time moved forward (players
// every tick, common infected every NextBot update). The plugin stores its own record next to it,
// with everything it needs later to rebuild what a client drew at any time in the history.
// ---------------------------------------------------------------------------

// Resolves the member offsets the recorder reads directly (once per map; they are the same for
// every class that inherits them).
bool ResolveOffsets(int entity)
{
	if (g_bBaseOffsets)
		return (g_iOffPose != -1 && g_iOffSimTime != -1);
	g_bBaseOffsets = true;

	g_iOffPose = FindDataMapInfo(entity, "m_flPoseParameter");
	g_iOffSimTime = FindDataMapInfo(entity, "m_flSimulationTime");
	g_iOffParity = FindDataMapInfo(entity, "m_nNewSequenceParity");   // optional: same-sequence restarts
	g_iOffModelIndex = FindDataMapInfo(entity, "m_nModelIndex");
	g_iOffAbsOrigin = FindDataMapInfo(entity, "m_vecAbsOrigin");
	g_iOffAbsRotation = FindDataMapInfo(entity, "m_angAbsRotation");
	g_iOffSequence = FindDataMapInfo(entity, "m_nSequence");
	g_iOffCycle = FindDataMapInfo(entity, "m_flCycle");
	g_iOffRate = FindDataMapInfo(entity, "m_flPlaybackRate");
	g_iOffEffects = FindDataMapInfo(entity, "m_fEffects");
	g_iOffAbsVelocity = FindDataMapInfo(entity, "m_vecAbsVelocity");
	g_iOffNoInterpParity = FindSendPropInfo("CTerrorPlayer", "m_ubEFNoInterpParity");
	g_iOffMainSeqStart = FindSendPropInfo("CTerrorPlayer", "m_mainSequenceStartTime");
	g_iOffEyeAng = FindSendPropInfo("CTerrorPlayer", "m_angEyeAngles[0]");
	if (g_iOffModelIndex == -1 || g_iOffAbsOrigin == -1 || g_iOffSequence == -1 || g_iOffCycle == -1
		|| g_iOffRate == -1 || g_iOffEffects == -1 || g_iOffAbsVelocity == -1)
	{
		LogError("Missing datamap offsets, recording is off.");
		g_iOffPose = -1;
	}
	return (g_iOffPose != -1 && g_iOffSimTime != -1);
}

// Which sm_posesync_targets bit an entity belongs to.
int ClassifyEntity(int entity)
{
	if (entity <= MaxClients)
	{
		if (!IsClientInGame(entity))
			return TARGET_OTHER;
		int team = GetClientTeam(entity);
		if (team == 2) return TARGET_SURVIVOR;
		if (team == 3) return TARGET_SPECIAL;
		return TARGET_OTHER;
	}

	char cls[64];
	GetEntityClassname(entity, cls, sizeof(cls));
	if (StrEqual(cls, "infected") || StrEqual(cls, "witch"))
		return TARGET_COMMON;
	return TARGET_OTHER;
}

// CLagCompensationManager::RecordDataIntoTrack, post: the engine just stored a record.
MRESReturn Detour_Record_Post(DHookParam hParams)
{
	if (!g_bEnabled)
		return MRES_Ignored;

	int entity = hParams.IsNull(1) ? -1 : hParams.Get(1);
	if (entity <= 0 || entity >= MAX_ENTS)
		return MRES_Ignored;

	if (g_bProfiling)
	{
		g_hProf.Start();
		RecordFiltered(entity);
		g_hProf.Stop();
		g_fProfRecord += g_hProf.Time;
		g_iProfRecords++;
		int tick = GetGameTickCount();
		if (tick != g_iProfLastTick)
		{
			g_iProfLastTick = tick;
			g_iProfTicks++;
		}
	}
	else
		RecordFiltered(entity);
	return MRES_Ignored;
}

// Per-entity cache (does it have pose parameters, its sequence start time offset, its class), then record.
void RecordFiltered(int entity)
{
	int ref = EntIndexToEntRef(entity);
	if (g_iCacheRef[entity] != ref)
	{
		if (!IsValidEntity(entity))
			return;
		g_iCacheRef[entity] = ref;
		g_bCacheHasPose[entity] = HasEntProp(entity, Prop_Data, "m_flPoseParameter");
		g_iCacheSeqStart[entity] = -1;
		g_iCacheOverlay[entity] = -1;
		g_bCacheCI[entity] = false;
		if (g_bCacheHasPose[entity])
		{
			ResolveOffsets(entity);
			g_iCacheOverlay[entity] = FindDataMapInfo(entity, "m_AnimOverlay");
			char net[64];
			bool haveNet = entity > MaxClients && GetEntityNetClass(entity, net, sizeof(net));
			// m_clientAnimatedOverlay is read at the gamedata offset, which was checked against
			// Infected's m_clientLeanYaw; check this class (Infected or Witch) the same way
			g_bCacheCI[entity] = haveNet && g_iOffCIOverlay > 0 && HasEntProp(entity, Prop_Send, "m_clientAnimatedOverlay")
				&& FindSendPropInfo(net, "m_clientLeanYaw") + 4 == g_iOffCIOverlay;
			if (haveNet && HasEntProp(entity, Prop_Send, "m_sequenceStartTime"))
				g_iCacheSeqStart[entity] = FindSendPropInfo(net, "m_sequenceStartTime");
			g_iClass[entity] = ClassifyEntity(entity);
		}
	}
	if (!g_bCacheHasPose[entity] || g_iOffPose == -1 || g_iOffSimTime == -1)
		return;
	RecordEntity(entity);
}

// Appends one record to the entity's history ring.
void RecordEntity(int entity)
{
	int ref = g_iCacheRef[entity];
	if (g_hHistory[entity] == null || g_iHistRef[entity] != ref || g_iHistLen[entity] != g_iRingSize)
	{
		delete g_hHistory[entity];
		g_hHistory[entity] = new ArrayList(REC_SIZE, g_iRingSize);
		g_iHistLen[entity] = g_iRingSize;
		g_iHistRef[entity] = ref;
		g_iHead[entity] = 0;
		g_iCount[entity] = 0;
	}

	float sim = GetEntDataFloat(entity, g_iOffSimTime);
	if (sim > g_fLatestSim)
		g_fLatestSim = sim;
	bool real = true;

	// The engine only adds a record when the simulation time moved forward (commons: every 0.1 s).
	if (g_iCount[entity] > 0 && sim <= g_fHeadSim[entity])
	{
		// Common infected / witches: CBaseEntity only moves m_flSimulationTime forward when the
		// origin or angles change (SetLocalOrigin / SetLocalAngles), so one standing still keeps
		// its old time while its NextBot goes on changing sequences (idle -> alert -> acquire;
		// Infected::OnSequenceSet sets m_sequenceStartTime). The client gets each change in the next
		// snapshot and plays it; the engine never records it. Record it at the present time, so
		// the rewind uses the sequence the client is playing.
		if (entity <= MaxClients || g_iCacheSeqStart[entity] <= 0
			|| (GetEntData(entity, g_iCacheSeqStart[entity]) == g_iHeadSeqStart[entity]
				&& (!g_bCacheCI[entity] || ClientOverlayHash(entity) == g_iHeadCIHash[entity])))
			return;
		sim = GetGameTime();
		if (sim <= g_fHeadSim[entity])
			return;
		g_iStatIdleSeq++;
		real = false;
	}

	// players change team / class: classified again after spawning, a team change, or a reset history
	if (entity <= MaxClients && (g_bReclassify[entity] || g_iCount[entity] == 0))
	{
		g_iClass[entity] = ClassifyEntity(entity);
		g_bReclassify[entity] = false;
	}
	if (!(g_iTargets & g_iClass[entity]))
		return;

	// one buffer for every record: every field read later is written below (layer slots past
	// REC_NLAYERS are never read), so it does not need clearing
	static int rec[REC_SIZE];
	rec[REC_SIM] = view_as<int>(sim);
	rec[REC_MODEL] = GetEntData(entity, g_iOffModelIndex, 2);
	for (int i = 0; i < MAXPOSE; i++)
		rec[REC_POSE + i] = view_as<int>(GetEntDataFloat(entity, g_iOffPose + i * 4));
	rec[REC_ORG] = GetEntData(entity, g_iOffAbsOrigin);
	rec[REC_ORG + 1] = GetEntData(entity, g_iOffAbsOrigin + 4);
	rec[REC_ORG + 2] = GetEntData(entity, g_iOffAbsOrigin + 8);
	rec[REC_AYAW] = (g_iOffAbsRotation > 0) ? GetEntData(entity, g_iOffAbsRotation + 4) : 0;
	rec[REC_TICK] = GetGameTickCount();
	rec[REC_REAL] = real ? 1 : 0;
	rec[REC_VEL] = GetEntData(entity, g_iOffAbsVelocity);
	rec[REC_VEL + 1] = GetEntData(entity, g_iOffAbsVelocity + 4);
	rec[REC_VEL + 2] = GetEntData(entity, g_iOffAbsVelocity + 8);
	rec[REC_SEQ]= GetEntData(entity, g_iOffSequence);
	rec[REC_CYCLE] = GetEntData(entity, g_iOffCycle);
	rec[REC_RATE] = GetEntData(entity, g_iOffRate);
	rec[REC_PARITY] = (g_iOffParity > 0) ? GetEntData(entity, g_iOffParity) : 0;
	rec[REC_HASYAW] = 0;
	rec[REC_RESET] = 0;
	rec[REC_HASEYE] = 0;
	rec[REC_NLAYERS] = 0;
	rec[REC_CICOUNT] = 0;
	g_iHeadCIHash[entity] = 0;
	if (g_bCacheCI[entity])
		g_iHeadCIHash[entity] = ReadClientOverlays(entity, rec);
	if (entity > MaxClients)
		rec[REC_SEQSTART] = (g_iCacheSeqStart[entity] > 0) ? GetEntData(entity, g_iCacheSeqStart[entity]) : view_as<int>(-1.0);
	else
	{
		int par = (g_iOffNoInterpParity > 0) ? GetEntData(entity, g_iOffNoInterpParity, 1) : 0;
		// The client resets its interpolation on EF_NOINTERP, on a no-interp parity bump and when it
		// gets the player new: a spawn (the first record of a life) here, entering the shooter's
		// snapshots per shooter in Hook_PlayerTransmit. For RESET_WINDOW_TIME after that it draws the
		// newest position it has, undelayed, with a 0 speed estimate (see FindResetWindow). The window
		// counts from the spawn, not from the first movement: a Jockey that stood for 0.23 s before
		// running had a 0 speed estimate on the client for only the first 4 frames of the run
		// (anim_showstate).
		if ((GetEntData(entity, g_iOffEffects) & 8) || g_iCount[entity] == 0
			|| par != g_iLastParity[entity])
		{
			rec[REC_RESET] = 1;
			g_fResetSim[entity] = sim;
		}
		g_iLastParity[entity] = par;

		Address anim = GetAnimState(entity);
		if (anim != Address_Null)
		{
			rec[REC_RYAW] = LoadFromAddress(anim + view_as<Address>(g_iOffRenderYaw), NumberType_Int32);
			rec[REC_HASYAW] = 1;
		}
		if (g_iOffEyeAng > 0)
		{
			rec[REC_EYEP] = GetEntData(entity, g_iOffEyeAng);
			rec[REC_EYEY] = GetEntData(entity, g_iOffEyeAng + 4);
			rec[REC_HASEYE] = 1;
		}
		rec[REC_SEQSTART] = (g_iOffMainSeqStart > 0) ? GetEntData(entity, g_iOffMainSeqStart) : view_as<int>(-1.0);
		if (g_bLayersOK)
		{
			int layerCount;
			int elems = LayerBase(entity, layerCount);
			if (layerCount > MAX_REC_LAYERS)
				layerCount = MAX_REC_LAYERS;
			for (int k = 0; k < layerCount && elems != 0; k++)
			{
				Address a = view_as<Address>(elems + k * LAYER_SIZE);
				int b = REC_LAYERS + k * REC_LSTRIDE;
				rec[b] = LoadI(a, LAYER_FLAGS);
				rec[b + 1] = LoadI(a, LAYER_SEQUENCE);
				rec[b + 2] = LoadI(a, LAYER_CYCLE);
				rec[b + 3] = LoadI(a, LAYER_WEIGHT);
				rec[b + 4] = LoadI(a, LAYER_ORDER);
				rec[REC_NLAYERS] = k + 1;
			}
		}
		NoteLockStart(entity, rec);
	}
	int head = (g_iCount[entity] == 0) ? 0 : (g_iHead[entity] + 1) % g_iRingSize;
	g_hHistory[entity].SetArray(head, rec);
	g_iHead[entity] = head;
	g_fHeadSim[entity] = sim;
	g_iHeadSeq[entity] = rec[REC_SEQ];
	g_iHeadSeqStart[entity] = rec[REC_SEQSTART];
	if (g_iCount[entity] < g_iRingSize)
		g_iCount[entity]++;

	g_iStatRecords++;
}

// ---------------------------------------------------------------------------
// Rewinding
//
// The engine calls BacktrackEntity once per lag compensated entity of a command. The pre hook writes
// the pose parameters, body yaw and target times of what the client drew; the post hook replaces the
// sequence and cycle the engine wrote with the client's and adds the client's crossfade.
// ---------------------------------------------------------------------------

// Pre hooks are wrapped so sm_posesync_profile can time them.
MRESReturn Detour_Backtrack_Pre(DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bProfiling)
		return Detour_Backtrack_Pre_Impl(hReturn, hParams);
	g_hProf.Start();
	MRESReturn r = Detour_Backtrack_Pre_Impl(hReturn, hParams);
	g_hProf.Stop();
	g_fProfRewind += g_hProf.Time;
	return r;
}

// CLagCompensationManager::BacktrackEntity, pre. Parameter 2 is the engine's target time
// (the command's tick_count minus the shooter's lerp; latency is already in tick_count).
MRESReturn Detour_Backtrack_Pre_Impl(DHookReturn hReturn, DHookParam hParams)
{
	#pragma unused hReturn
	if (!g_bEnabled)
		return MRES_Ignored;

	int entity = hParams.IsNull(1) ? -1 : hParams.Get(1);
	if (entity <= 0 || entity >= MAX_ENTS || !IsValidEntity(entity))
		return MRES_Ignored;

	g_iStatBacktracks++;
	if (g_iAppliedCount == 0)
	{
		g_iPassShooter = g_iShooter;
		g_iPassTick = GetGameTickCount();
	}
	if (g_bProfiling)
		g_iProfRewinds++;
	DbgBeginPass();

	if (g_bApplied[entity])
	{
		// Already rewound in this lag compensation pass (a nested StartLagCompensation): put the
		// plugin's overlay layers back first, so the engine does not take them as the state to
		// restore; the post hook applies them again.
		if (g_iTransCount[entity] > 0)
			RestoreTransitionLayers(entity);
		return MRES_Ignored;
	}

	float target = hParams.Get(2);

	if (g_hHistory[entity] == null || g_iCount[entity] == 0 || g_iHistRef[entity] != EntIndexToEntRef(entity)
		|| !(g_iTargets & g_iClass[entity]))
	{
		g_iStatNoHistory++;
		if (g_iDebug > 0)
			Dbg(entity, "[posesync] ent %d: skipped, %s (target %.3f)", entity,
				g_hHistory[entity] == null || g_iCount[entity] == 0 ? "no pose history" :
				g_iHistRef[entity] != EntIndexToEntRef(entity) ? "history belongs to an older entity" : "not in sm_posesync_targets", target);
		return MRES_Ignored;
	}

	bool changed = false, inWindow = false;
	bool shooter = g_iShooter > 0 && g_iShooter <= MaxClients;
	float cvarLerp;
	float lerp = shooter ? GetShooterLerp(g_iShooter, cvarLerp) : 0.0;

	// One report per shot: how far the engine rewinds and how much of that is latency.
	if (shooter && g_fLatestSim > 0.0)
	{
		float allow = g_fLatestSim - target - lerp;
		if (allow < 0.0)
			allow = 0.0;
		g_fPingAllow[g_iShooter] = allow;
		if (g_iDebug > 0 && g_iPingReportTick[g_iShooter] != GetGameTickCount())
		{
			g_iPingReportTick[g_iShooter] = GetGameTickCount();
			Dbg(0, "[posesync] lag compensation for %N (shot or shove): engine target %.3f is %.1f ticks behind the newest record = lerp %.0f ms + latency allowance %.0f ms (net latency out %.0f ms)",
				g_iShooter, target, (g_fLatestSim - target) / g_fTick, lerp * 1000.0, allow * 1000.0,
				IsFakeClient(g_iShooter) ? 0.0 : GetClientLatency(g_iShooter, NetFlow_Outgoing) * 1000.0);
		}
	}

	// Interpolation reset window: the client draws the newest position it has, without its usual
	// delay, so rewind everything (the engine's origin/sequence/cycle/layers too) to that time.
	float wDisplay, wReset;
	g_bCycleSaved[entity] = false;
	if (entity <= MaxClients
		&& FindResetWindow(entity, target, wDisplay, wReset))
	{
		inWindow = true;
		if (wDisplay > target)
		{
			if (g_iDebug > 0)
				Dbg(entity, "[posesync] ent %d: %.1f ticks after an interpolation reset: target time %.3f -> %.3f (what the client draws)",
					entity, (wDisplay - wReset) / g_fTick, target, wDisplay);
			target = wDisplay;
			hParams.Set(2, target);
			changed = true;
		}
	}

	float poses[MAXPOSE];
	float recSim, prevSim, frac, yaw;
	bool haveYaw;
	if (!LookupPoses(entity, target, poses, recSim, prevSim, frac, yaw, haveYaw))
	{
		g_iStatNoHistory++;
		if (g_iDebug > 0)
			Dbg(entity, "[posesync] ent %d: skipped, model changed since the record at the target time (target %.3f)", entity, target);
		return changed ? MRES_ChangedHandled : MRES_Ignored;
	}

	// keep the present pose parameters to put back in FinishLagCompensation
	for (int i = 0; i < MAXPOSE; i++)
		g_fSaved[entity * MAXPOSE + i] = GetEntDataFloat(entity, g_iOffPose + i * 4);
	g_iAppliedModel[entity] = ModelIndexOf(entity);
	g_bSeqSaved[entity] = false;
	g_bWroteSeq[entity] = false;
	g_bWroteCycle[entity] = false;
	g_iTransCount[entity] = 0;
	g_bTransSnap[entity] = false;
	g_bSparseMoved[entity] = false;
	g_bHeld[entity] = false;
	g_bInWindow[entity] = inWindow;

	if (inWindow)
		ApplyResetWindow(entity, poses, wDisplay, wReset);

	// Animation frame on the client clock: players, and common infected / witches (their cycle is
	// not networked; the client starts the sequence from m_sequenceStartTime on its own clock).
	g_bClockMain[entity] = false;
	g_fAnimTarget[entity] = target;
	g_bAnimTarget[entity] = true;
	if (!inWindow && (entity <= MaxClients || g_iClass[entity] == TARGET_COMMON))
		PrepareClientClockMain(entity, target);

	// Position time: the client draws other entities TICKS_TO_TIME(TIME_TO_TICKS(lerp) + 1)
	// behind its clock, and its command's tick_count is one tick behind that clock, so what it draws
	// is tick_count - whole lerp ticks. The engine rewinds to tick_count - lerp (exact), which is
	// lerp - whole lerp ticks too early (or too late when the lerp rounds up). Origin, angles and the
	// body yaw move by that difference; the animation frame stays on g_fAnimTarget.
	float posTarget = target;
	if (!inWindow && shooter)
	{
		float ti = g_fTick;
		int lerpTicks = RoundToFloor(0.5 + lerp / ti);
		float posShift = lerp - float(lerpTicks) * ti;
		if (FloatAbs(posShift) > 0.0001)
		{
			posTarget = target + posShift;
			hParams.Set(2, posTarget);
			changed = true;
			if (haveYaw)
			{
				float tp[MAXPOSE], rs, ps, fr, yaw2;
				bool have2;
				if (LookupPoses(entity, posTarget, tp, rs, ps, fr, yaw2, have2) && have2)
					yaw = yaw2;
			}
		}
		if (g_iDebug > 0)
			Dbg(entity, "[posesync] ent %d position: lerp %.1f ms = %d whole ticks + %s%.1f ms -> origin and angles rewound to %.3f (what the client draws) instead of %.3f (engine)",
				entity, lerp * 1000.0, lerpTicks, posShift >= 0.0 ? "" : "-", FloatAbs(posShift) * 1000.0, posTarget, target);
	}

	// players: aim and body yaw from the eye angles the client drew with
	g_bEyeLocked = false;
	if (!inWindow && entity <= MaxClients)
		ApplyEyeDriven(entity, target, posTarget, poses, yaw, haveYaw);

	// players: feet and aim yaw as the client turned them after a spawn (its speed estimate is 0 in
	// the reset window)
	if (entity <= MaxClients && haveYaw && !g_bEyeLocked)
		ApplyClientSpawnTurn(entity, inWindow ? target : posTarget, poses, yaw);

	// players: move blend (and the Hunter's pounce blend) from the client's velocity estimate
	if (!inWindow && entity <= MaxClients && haveYaw)
		ApplyClientMoveBlend(entity, posTarget, poses, yaw);

	if (g_iDebug > 0)
	{
		DebugRewind(entity, target, recSim, prevSim, frac, poses);
		if (g_iClass[entity] == TARGET_COMMON)
			DebugCommonExtrapolation(entity, posTarget, target);
	}

	for (int i = 0; i < MAXPOSE; i++)
		SetEntDataFloat(entity, g_iOffPose + i * 4, poses[i], false);

	// players: the render yaw the server builds the bones with
	g_bYawSaved[entity] = false;
	if (haveYaw)
	{
		Address anim = GetAnimState(entity);
		if (anim != Address_Null)
		{
			float now = LoadAnimFloat(anim, g_iOffRenderYaw);
			g_fSavedYaw[entity] = now;
			g_aSavedAnim[entity] = anim;
			g_bYawSaved[entity] = true;
			StoreToAddress(anim + view_as<Address>(g_iOffRenderYaw), yaw, NumberType_Int32, false);
			if (g_iDebug > 0)
			{
				float eye = (g_iOffEyeYaw != -1) ? LoadAnimFloat(anim, g_iOffEyeYaw) : 0.0;
				float goal = (g_iOffGoalFeetYaw != -1) ? LoadAnimFloat(anim, g_iOffGoalFeetYaw) : 0.0;
				Dbg(entity, "[posesync] ent %d body yaw now %.1f -> rewound %.1f (%s%.1f deg; eye yaw now %.1f, goal feet yaw now %.1f)",
					entity, now, yaw, AngleDiff(yaw, now) >= 0.0 ? "+" : "", AngleDiff(yaw, now), eye, goal);
			}
		}
	}

	g_bApplied[entity] = true;
	g_iAppliedRef[entity] = EntIndexToEntRef(entity);
	g_iAppliedList[g_iAppliedCount++] = entity;
	g_iStatApplied++;

	FlushBones(entity);
	return changed ? MRES_ChangedHandled : MRES_Ignored;
}

MRESReturn Detour_Backtrack_Post(DHookReturn hReturn, DHookParam hParams)
{
	if (!g_bProfiling)
		return Detour_Backtrack_Post_Impl(hReturn, hParams);
	g_hProf.Start();
	MRESReturn r = Detour_Backtrack_Post_Impl(hReturn, hParams);
	g_hProf.Stop();
	g_fProfRewind += g_hProf.Time;
	return r;
}

// CLagCompensationManager::BacktrackEntity, post: the engine has moved the entity and written its own
// sequence, cycle and layers for the target time (for gunshots only with the StartLagCompensation
// detour; otherwise they are still the present ones).
MRESReturn Detour_Backtrack_Post_Impl(DHookReturn hReturn, DHookParam hParams)
{
	int entity = hParams.IsNull(1) ? -1 : hParams.Get(1);
	if (entity <= 0 || entity >= MAX_ENTS)
		return MRES_Ignored;
	if (!g_bEnabled && !g_bApplied[entity])
		return MRES_Ignored;

	// BacktrackEntity also returns false when there is nothing to move: the record at the target
	// time is where the entity already is (a common standing still, or one whose simulation time
	// has not moved). Its animation frame still has to be the client's.
	bool rewound = hReturn.Value;
	bool inPlace = false;
	// sparse records: the engine refused over a gap between its records that the client
	// interpolated across (checked first: an entity standing at its newest record can still have
	// the gap between that record and the target time)
	if (!rewound && g_bApplied[entity] && g_bEnabled && g_bCanMove && IsValidEntity(entity)
		&& SparseRewind(entity, hParams.Get(2)))
		rewound = true;
	if (!rewound && g_bApplied[entity] && IsValidEntity(entity) && NothingToMove(entity, hParams.Get(2)))
	{
		rewound = true;
		inPlace = true;
	}

	// only entities the pre hook accepted (in sm_posesync_targets, history of the same model)
	bool active = rewound && g_bEnabled && g_bApplied[entity] && IsValidEntity(entity);
	bool common = entity > MaxClients && g_iClass[entity] == TARGET_COMMON;
	if (active && g_iTransCount[entity] == 0)
	{
		float target = g_bAnimTarget[entity] ? g_fAnimTarget[entity] : view_as<float>(hParams.Get(2));
		bool animChanged = false;
		if (g_bClockMain[entity])
		{
			// the engine has just written its own (target time) sequence and cycle
			WriteSequence(entity, g_iClockSeq[entity]);
			WriteCycle(entity, g_fClockCycle[entity]);
			animChanged = true;
			if (entity <= MaxClients)
				ApplyClientClockLayers(entity, target);
			else if (g_bCacheCI[entity])
				ApplyCommonOverlays(entity, target);
		}
		if (ApplyTransitions(entity, target))
			animChanged = true;
		if (g_iTransCount[entity] > 0)
			SnapshotWrittenLayers(entity);
		if (animChanged)
			FlushBones(entity);
	}

	// players, common infected and witches: where the shooter's client drew it (a Hermite curve
	// through the samples it received, or its newest one held when it draws past it)
	if (active && !inPlace && g_bCanMove && !g_bSparseMoved[entity] && !g_bInWindow[entity]
		&& (entity <= MaxClients || common) && MoveToClientPosition(entity, hParams.Get(2)))
		FlushBones(entity);

	// common infected / witches: the client's own aim at its look-at target (from where it was
	// rewound to) and its move blend from its velocity estimate
	if (active && common)
	{
		bool aim = ApplyCommonAim(entity, hParams.Get(2));
		if (ApplyCommonMove(entity, hParams.Get(2)) || aim)
			FlushBones(entity);
	}

	// players attached to this one moved with it
	if (rewound && entity <= MaxClients && g_bEnabled)
		FlushFollowers(entity);

	// Where the hitboxes are built: compare with the client's "Loc:" / "FeetYaw:" from
	// cl_showanimstate <ent> at the frame of the shot.
	if (g_iDebug > 0 && inPlace)
		Dbg(entity, "[posesync] ent %d: the engine left it in place (nothing to move: the record at the target time is where it already is); pose and animation frame still set", entity);
	if (g_iDebug > 0 && rewound && IsValidEntity(entity))
	{
		float org[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);
		Address anim = (entity <= MaxClients) ? GetAnimState(entity) : Address_Null;
		if (anim != Address_Null)
			Dbg(entity, "[posesync] ent %d rewound to: Loc %.2f %.2f %.2f, body (feet) yaw %.2f, time %.3f",
				entity, org[0], org[1], org[2], LoadAnimFloat(anim, g_iOffRenderYaw), view_as<float>(hParams.Get(2)));
		else
		{
			float ang[3];
			GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
			Dbg(entity, "[posesync] ent %d rewound to: Loc %.2f %.2f %.2f, yaw %.2f, time %.3f",
				entity, org[0], org[1], org[2], ang[1], view_as<float>(hParams.Get(2)));
		}
	}

	// This is the exact state the engine builds the rewound (blue) hitboxes from.
	if (g_iDebug >= 3 && IsValidEntity(entity))
		DumpAnimState(entity, rewound ? "rewound state used for the hitboxes" : "engine did not rewind, present state");

	if (!g_bApplied[entity])
		return MRES_Ignored;

	// Engine lost track (dead record, teleport, ...) and left the entity at the
	// present. Keep the pose consistent with that.
	if (!rewound)
	{
		g_iStatEngineRejected++;
		if (g_iDebug > 0)
		{
			char why[160];
			RefusalReason(entity, hParams.Get(2), why, sizeof(why));
			Dbg(entity, "[posesync] ent %d: engine refused to rewind (%s), pose put back", entity, why);
		}
		RestoreEntity(entity);
		RemoveFromAppliedList(entity);
	}
	return MRES_Ignored;
}

// CLagCompensationManager::FinishLagCompensation, pre. The engine puts the overlay layers back inside
// FinishLagCompensation, so the crossfade slots the plugin borrowed are emptied before it runs
// (otherwise the plugin's own restore would overwrite the engine's with rewound values).
MRESReturn Detour_Finish_Pre(DHookParam hParams)
{
	if (!g_bProfiling)
		return Detour_Finish_Pre_Impl(hParams);
	g_hProf.Start();
	MRESReturn r = Detour_Finish_Pre_Impl(hParams);
	g_hProf.Stop();
	g_fProfRewind += g_hProf.Time;
	return r;
}

MRESReturn Detour_Finish_Pre_Impl(DHookParam hParams)
{
	#pragma unused hParams
	// Everything is still rewound here (layers, poses, yaw, the engine's origin), and the bone
	// cache holds the skeleton the bullet traces just used.
	DbgTakeAim(g_iShooter);
	if (g_bDraw)
		DrawShotHitboxes(g_iShooter);
	for (int i = 0; i < g_iAppliedCount; i++)
	{
		int entity = g_iAppliedList[i];
		if (EntRefToEntIndex(g_iAppliedRef[entity]) != entity)
			continue;
		if (g_iTransCount[entity] > 0)
			RestoreTransitionLayers(entity);
		UndoHold(entity);
	}
	return MRES_Ignored;
}

MRESReturn Detour_Finish_Post(DHookParam hParams)
{
	if (!g_bProfiling)
		return Detour_Finish_Post_Impl(hParams);
	g_hProf.Start();
	MRESReturn r = Detour_Finish_Post_Impl(hParams);
	g_hProf.Stop();
	g_fProfRewind += g_hProf.Time;
	return r;
}

// CLagCompensationManager::FinishLagCompensation, post: the engine has put its own state back; put back
// the pose parameters, sequence, cycle and render yaw of every entity the plugin rewound.
MRESReturn Detour_Finish_Post_Impl(DHookParam hParams)
{
	#pragma unused hParams
	RestoreAll();
	ReleaseFollowers();
	return MRES_Ignored;
}

// ---------------------------------------------------------------------------
// Gaps in the engine's own lag compensation
//
// CTerrorPlayer::WantsLagCompensationOnEntity(target, cmd, transmit bits) decides, per entity, whether
// StartLagCompensation rewinds it:
//   - false for every entity unless cmd->buttons has IN_ATTACK or IN_ATTACK2, or the command is within
//     5 command numbers of the last shove (CTerrorPlayer::OnMeleeAttack)
//   - false for a Jockey riding someone (m_jockeyVictim) and for a survivor a Charger carries
//     (m_carryAttacker): both are parented to the other player (CBaseEntity::SetParent), and
//     SetAbsOrigin on a child while its parent is rewound or put back would corrupt its local offset
//   - otherwise CBasePlayer::WantsLagCompensationOnEntity: no teammates (unless mp_friendlyfire), in
//     the transmit set, and near or in front of the shooter
// ---------------------------------------------------------------------------

// Swings: the shooter's active weapon is in a swing that tests for hits: a melee weapon
// between swing start and end (m_bInMeleeSwing), or any other weapon's swing timer (shove, special
// infected claws, Tank punch after its windup). CountdownTimer m_swingTimer: m_timestamp at +8 is when
// the swing ends, -1 once it has hit something.
bool IsSwinging(int client)
{
	if (g_iOffActiveWeapon <= 0)
		return false;
	int weapon = GetEntDataEnt2(client, g_iOffActiveWeapon);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return false;
	if (g_iOffInMeleeSwing > 0 && HasEntProp(weapon, Prop_Send, "m_bInMeleeSwing")
		&& GetEntData(weapon, g_iOffInMeleeSwing, 1) != 0)
		return true;
	if (g_iOffSwingTimer > 0 && HasEntProp(weapon, Prop_Send, "m_swingTimer"))
	{
		float ends = GetEntDataFloat(weapon, g_iOffSwingTimer + 8);
		if (ends > 0.0 && GetGameTime() <= ends + g_fTick)
			return true;
	}
	return false;
}

// Pre: while a swing is testing for hits, the command counts as an attack (IN_ATTACK for the length
// of this call; the post hook puts the buttons back). One answer per command: StartLagCompensation
// asks once per entity.
MRESReturn Detour_Wants_Pre(int shooter, DHookReturn hReturn, DHookParam hParams)
{
	#pragma unused hReturn
	// a patch the post hook never saw (another plugin superseded the call): put it back first
	UndoButtonPatch(shooter);
	if (!g_bEnabled || shooter <= 0 || shooter > MaxClients || hParams.IsNull(2))
		return MRES_Ignored;
	int buttons = hParams.GetObjectVar(2, CMD_BUTTONS, ObjectValueType_Int);
	if (buttons & (IN_ATTACK | IN_ATTACK2))
		return MRES_Ignored;

	static int cacheShooter, cacheCmd, cacheTick;
	static bool cacheSwing;
	int cmd = hParams.GetObjectVar(2, CMD_COMMAND_NUMBER, ObjectValueType_Int);
	int tick = GetGameTickCount();
	if (shooter != cacheShooter || cmd != cacheCmd || tick != cacheTick)
	{
		cacheShooter = shooter;
		cacheCmd = cmd;
		cacheTick = tick;
		cacheSwing = IsSwinging(shooter);
	}
	if (!cacheSwing)
		return MRES_Ignored;
	g_iPatchedButtons = buttons;
	g_aPatchedCmd = hParams.GetAddress(2);
	g_iPatchedShooter = shooter;
	g_iPatchedTick = GetGameTickCount();
	g_bButtonsPatched = true;
	hParams.SetObjectVar(2, CMD_BUTTONS, ObjectValueType_Int, buttons | IN_ATTACK);
	return MRES_Ignored;
}

// Puts back buttons the Wants pre hook changed and its post hook never restored. The command is
// only written to while it is still the one running (same player and tick); otherwise the patch is
// dropped, since that memory may already hold something else.
void UndoButtonPatch(int runningClient)
{
	if (!g_bButtonsPatched)
		return;
	g_bButtonsPatched = false;
	if (g_aPatchedCmd != Address_Null && runningClient == g_iPatchedShooter && GetGameTickCount() == g_iPatchedTick)
		StoreToAddress(g_aPatchedCmd + view_as<Address>(CMD_BUTTONS), g_iPatchedButtons, NumberType_Int32, false);
	g_aPatchedCmd = Address_Null;
}

// The game's attack test for this command (after the swing extension).
bool CommandAttacks(int shooter, DHookParam hParams, bool patched)
{
	if (patched)
		return true;
	if (hParams.GetObjectVar(2, CMD_BUTTONS, ObjectValueType_Int) & (IN_ATTACK | IN_ATTACK2))
		return true;
	if (g_iOffLastMeleeCmd > 0)
		return hParams.GetObjectVar(2, CMD_COMMAND_NUMBER, ObjectValueType_Int) - GetEntData(shooter, g_iOffLastMeleeCmd) <= 5;
	return false;
}

// Post: put the buttons back; Jockey-ridden survivors.
MRESReturn Detour_Wants_Post(int shooter, DHookReturn hReturn, DHookParam hParams)
{
	bool patched = g_bButtonsPatched;
	if (patched)
	{
		g_bButtonsPatched = false;
		hParams.SetObjectVar(2, CMD_BUTTONS, ObjectValueType_Int, g_iPatchedButtons);
	}
	if (!g_bEnabled)
		return MRES_Ignored;
	if (hReturn.Value)
	{
		if (patched)
			g_iStatSwing++;
		return MRES_Ignored;
	}

	// A survivor ridden by a Jockey the shooter is fighting. The game leaves the
	// survivor alone (a teammate) and the Jockey too (attached to the survivor), so the Jockey's
	// hitboxes stay at the present while the shooter's client drew it, attached to the survivor, at
	// the survivor's interpolated position. Rewinding the survivor moves the Jockey with it; nothing
	// is ever set on the Jockey itself, so its offset to the survivor stays intact.
	if (g_iOffJockeyAttacker <= 0 || shooter <= 0 || shooter > MaxClients || hParams.IsNull(1))
		return MRES_Ignored;
	int target = hParams.Get(1);
	if (target <= 0 || target > MaxClients || target == shooter || !IsClientInGame(target) || !IsPlayerAlive(target))
		return MRES_Ignored;
	int jockey = GetEntDataEnt2(target, g_iOffJockeyAttacker);
	if (jockey <= 0 || jockey > MaxClients || !IsClientInGame(jockey) || !IsPlayerAlive(jockey)
		|| GetClientTeam(jockey) == GetClientTeam(shooter))
		return MRES_Ignored;
	if (!CommandAttacks(shooter, hParams, patched))
		return MRES_Ignored;
	g_iStatRidden++;
	hReturn.Value = true;
	return MRES_Override;
}

// Animation rewind for gunshots: FireTerrorBullets calls StartLagCompensation(player,
// LAG_COMPENSATE_HITBOXES_ALONG_RAY, vec3_origin, vec3_angle, 0.0). BacktrackEntity then only rewinds
// the animation of entities within 100 units of a 0-length ray at the world origin, i.e. never. The
// same call as LAG_COMPENSATE_HITBOXES rewinds sequence, cycle and overlay layers for every entity.
MRESReturn Detour_Start_Pre(DHookParam hParams)
{
	if (!g_bEnabled)
		return MRES_Ignored;
	if (view_as<int>(hParams.Get(2)) != LAGCOMP_HITBOXES_ALONG_RAY || view_as<float>(hParams.Get(5)) > 0.0)
		return MRES_Ignored;
	hParams.Set(2, LAGCOMP_HITBOXES);
	g_iStatAnimRewind++;
	return MRES_ChangedHandled;
}

// ---------------------------------------------------------------------------
// Common infected aim
//
// DT_Infected excludes m_flPoseParameter: the client computes a common's pose parameters itself.
// C_Infected (client.dll 0x10313c60), every frame:
//   - body_yaw / body_pitch = AngleDiff(angles of (target eye - own eye), own abs angles), target =
//     m_clientLookatTarget's EyePosition() (no target: own eye + forward, i.e. 0 / 0)
//   - own eye = C_BaseEntity::EyePosition = abs origin + m_vecViewOffset, and a common's view offset is
//     never networked, so it stays 0: the client aims from the common's origin
//   - another player's eye = origin + the view offset C_TerrorPlayer sets once (m_vView, 0 0 62); the
//     local player (the shooter) uses its own predicted eye position
//   - lean_yaw = m_clientLeanYaw, lean_pitch = the centre of its range
// The server sets body_yaw / body_pitch only when the AI calls ZombieBotBody::AimHeadTowards, aiming
// from its own eye height at where the target was then, and sets lean_pitch from its locomotion. So
// a common attacking a survivor who moves, crouches or walks around it, or one whose look-at target
// just changed (the client snaps the upper body to the new target), has a different torso and head
// on the server.
// ---------------------------------------------------------------------------

// The look-at target's eye position as the shooter's client draws it at time t.
bool CommonAimTargetEye(int target, float t, float eye[3])
{
	if (target == g_iShooter && target > 0 && target <= MaxClients && IsClientInGame(target))
	{
		GetClientEyePosition(target, eye);
		return true;
	}
	if (target > 0 && target <= MaxClients)
	{
		if (!IsClientInGame(target))
			return false;
		int a[REC_SIZE], b[REC_SIZE];
		bool haveB;
		float frac;
		if (g_hHistory[target] != null && g_iHistRef[target] == EntIndexToEntRef(target)
			&& FindRecordPair(target, t, a, b, haveB, frac))
		{
			for (int i = 0; i < 3; i++)
			{
				float oa = view_as<float>(a[REC_ORG + i]);
				eye[i] = haveB ? oa + (view_as<float>(b[REC_ORG + i]) - oa) * frac : oa;
			}
		}
		else
			GetEntPropVector(target, Prop_Data, "m_vecAbsOrigin", eye);
		eye[2] += CLIENT_PLAYER_VIEW_Z;
		return true;
	}
	if (!IsValidEntity(target))
		return false;
	// not a player: m_vecViewOffset is only networked to the local player, so on the client its
	// EyePosition is its origin (as for the common itself, see above)
	GetEntPropVector(target, Prop_Data, "m_vecAbsOrigin", eye);
	return true;
}

// Normalised pose value for 'degrees' the way Studio_SetPoseParameter maps it (wrap for looping
// parameters, clamp otherwise).
float PoseValueFromDegrees(PoseModel pm, int i, float v)
{
	float s = pm.start[i], e = pm.end[i];
	if (e == s)
		return 0.0;
	if (pm.loop[i] != 0.0)
	{
		float wrap = (s + e) * 0.5 + pm.loop[i] * 0.5;
		float zero = (s + e) * 0.5 - pm.loop[i] * 0.5;
		if (v > wrap) v -= pm.loop[i];
		if (v < zero) v += pm.loop[i];
	}
	float n = (v - s) / (e - s);
	if (n < 0.0) n = 0.0;
	if (n > 1.0) n = 1.0;
	return n;
}

// Writes body_yaw, body_pitch and lean_pitch of a rewound common as its client computes them.
// Returns true if anything was written.
bool ApplyCommonAim(int entity, float t)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm) || !HasEntProp(entity, Prop_Send, "m_clientLookatTarget"))
		return false;
	int iYaw = pm.idxBodyYaw, iPitch = pm.idxBodyPitch, iLeanPitch = pm.idxLeanPitch;
	if (iYaw == -1 && iPitch == -1 && iLeanPitch == -1)
		return false;

	float org[3], ang[3], eye[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
	int target = GetEntPropEnt(entity, Prop_Send, "m_clientLookatTarget");
	float yawDiff = 0.0, pitchDiff = 0.0;
	bool aimed = false;
	if (target > 0 && CommonAimTargetEye(target, t, eye))
	{
		float dir[3], a[3];
		SubtractVectors(eye, org, dir);
		if (GetVectorLength(dir) > 0.001)
		{
			NormalizeVector(dir, dir);
			GetVectorAngles(dir, a);
			yawDiff = AngleDiff(a[1], ang[1]);
			pitchDiff = AngleDiff(a[0], ang[0]);
			aimed = true;
		}
	}

	float before[3];
	if (iYaw != -1)
	{
		before[0] = GetEntDataFloat(entity, g_iOffPose + iYaw * 4);
		SetEntDataFloat(entity, g_iOffPose + iYaw * 4, PoseValueFromDegrees(pm, iYaw, yawDiff), false);
	}
	if (iPitch != -1)
	{
		before[1] = GetEntDataFloat(entity, g_iOffPose + iPitch * 4);
		SetEntDataFloat(entity, g_iOffPose + iPitch * 4, PoseValueFromDegrees(pm, iPitch, pitchDiff), false);
	}
	// lean_yaw: the client sets it from m_clientLeanYaw, which it has as of its newest update (the
	// server's lean_yaw is the same value, but at the engine's target time)
	if (pm.idxLeanYaw != -1 && g_hHistory[entity] != null)
	{
		int n;
		int idx = FindRecIndex(entity, SampleClock(entity, t), n);
		if (idx != -1)
			SetEntDataFloat(entity, g_iOffPose + pm.idxLeanYaw * 4, view_as<float>(g_hHistory[entity].Get(idx, REC_POSE + pm.idxLeanYaw)), false);
	}
	if (iLeanPitch != -1)
	{
		before[2] = GetEntDataFloat(entity, g_iOffPose + iLeanPitch * 4);
		SetEntDataFloat(entity, g_iOffPose + iLeanPitch * 4, PoseValueFromDegrees(pm, iLeanPitch, (pm.start[iLeanPitch] + pm.end[iLeanPitch]) * 0.5), false);
	}
	if (g_iDebug > 0)
	{
		float sy = (iYaw != -1) ? pm.start[iYaw] + before[0] * (pm.end[iYaw] - pm.start[iYaw]) : 0.0;
		float sp = (iPitch != -1) ? pm.start[iPitch] + before[1] * (pm.end[iPitch] - pm.start[iPitch]) : 0.0;
		float sl = (iLeanPitch != -1) ? pm.start[iLeanPitch] + before[2] * (pm.end[iLeanPitch] - pm.start[iLeanPitch]) : 0.0;
		if (aimed)
			Dbg(entity, "[posesync] ent %d (common) client aim at its look-at target ent %d: body_yaw %.1f (server %.1f), body_pitch %.1f (server %.1f), lean_pitch centred (server %.1f)",
				entity, target, yawDiff, sy, pitchDiff, sp, sl);
		else
			Dbg(entity, "[posesync] ent %d (common) has no look-at target on the client: body_yaw 0 (server %.1f), body_pitch 0 (server %.1f), lean_pitch centred (server %.1f)",
				entity, sy, sp, sl);
	}
	return true;
}

// ---------------------------------------------------------------------------
// Common infected overlay layers
//
// DT_Infected does not send the overlay layers; it sends m_clientAnimatedOverlay instead, a copy of
// the first 6 layers made by Infected::UpdateClientAnimationLayers on each NextBot update: sequence,
// order (6 = off), looping, and m_flStartTime = the server time the layer started (or restarted).
// The client animates each one itself (C_Infected, client.dll 0x10314ef0), into its overlay slot i
// with order i:
//   cycle  = (curtime - start time) x the sequence's cycle rate; past 1 a looping layer wraps and a
//            non-looping one is switched off
//   weight = 1, faded in over the sequence's fade-in time at its start and out over its fade-out
//            time at its end (a looping layer stops fading after half its length; STUDIO_SNAP: none)
// The server's own layers have their own cycles and weights (attack swings, flinches), and the
// engine records them only when the simulation time moves, so a common that stops to attack had
// its swing missing from the rewound skeleton.
// ---------------------------------------------------------------------------

// Copies m_clientAnimatedOverlay into a record; returns a hash of it (to see a change).
int ReadClientOverlays(int entity, int rec[REC_SIZE])
{
	Address vec = GetEntityAddress(entity) + view_as<Address>(g_iOffCIOverlay);
	int elems = LoadFromAddress(vec, NumberType_Int32);
	int count = LoadFromAddress(vec + view_as<Address>(12), NumberType_Int32);
	if (elems == 0 || count <= 0)
		return 0;
	if (count > MAX_CI_LAYERS)
		count = MAX_CI_LAYERS;
	int hash = count;
	for (int i = 0; i < count; i++)
	{
		Address e = view_as<Address>(elems + i * CI_ELEM_SIZE);
		int o = REC_CI + i * REC_CISTRIDE;
		rec[o] = LoadI(e, 4);
		rec[o + 1] = LoadI(e, 8);
		rec[o + 2] = (LoadI(e, 12) & 0xFF) | ((LoadFromAddress(e + view_as<Address>(16), NumberType_Int8) & 1) << 8);
		hash = hash * 31 + rec[o];
		hash = hash * 31 + rec[o + 1];
		hash = hash * 31 + rec[o + 2];
	}
	rec[REC_CICOUNT] = count;
	return hash;
}

// Notes the first snapshot that carried each overlay slot's start time to the client. The entity's
// start times are read once per tick; a client's slots are only compared again when one changed.
void TrackOverlayStarts(int entity, int client, float now, bool again = false)
{
	int tick = GetGameTickCount();
	if (g_iOvTick[entity] != tick)
	{
		g_iOvTick[entity] = tick;
		Address vec = GetEntityAddress(entity) + view_as<Address>(g_iOffCIOverlay);
		int elems = LoadFromAddress(vec, NumberType_Int32);
		int count = LoadFromAddress(vec + view_as<Address>(12), NumberType_Int32);
		if (elems == 0 || count < 0)
			count = 0;
		if (count > MAX_CI_LAYERS)
			count = MAX_CI_LAYERS;
		bool changed = (count != g_iOvCount[entity]);
		for (int i = 0; i < count; i++)
		{
			float start = view_as<float>(LoadI(view_as<Address>(elems + i * CI_ELEM_SIZE), 8));
			if (start != g_fOvStart[entity * MAX_CI_LAYERS + i])
			{
				g_fOvStart[entity * MAX_CI_LAYERS + i] = start;
				changed = true;
			}
		}
		g_iOvCount[entity] = count;
		if (changed)
			g_iOvVer[entity]++;
	}
	if (!again && g_iTxOvVer[client][entity] == g_iOvVer[entity])
		return;
	g_iTxOvVer[client][entity] = g_iOvVer[entity];
	for (int i = 0; i < g_iOvCount[entity]; i++)
	{
		if (again || g_fOvStart[entity * MAX_CI_LAYERS + i] != g_fTxOvStart[client][entity * MAX_CI_LAYERS + i])
		{
			g_fTxOvStart[client][entity * MAX_CI_LAYERS + i] = g_fOvStart[entity * MAX_CI_LAYERS + i];
			g_fTxOvSeen[client][entity * MAX_CI_LAYERS + i] = now;
		}
	}
}

// The same hash straight from the entity (a change without a new simulation time).
int ClientOverlayHash(int entity)
{
	static int tmp[REC_SIZE];
	return ReadClientOverlays(entity, tmp);
}

// Overlay slots 0..5 of a rewound common, as its client animates them at the client clock.
bool ApplyCommonOverlays(int entity, float target)
{
	if (!g_bLayersOK)
		return false;
	PoseModel pm;
	if (!GetPoseModel(entity, pm) || pm.seqInfo == null)
		return false;
	float cvarLerp;
	// the same clock as the main sequence: the client animates both from the start times on one clock
	float clock = ClientClock(entity, target, GetShooterLerp(g_iShooter, cvarLerp));
	int a[REC_SIZE], b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, clock, a, b, haveB, frac))
		return false;
	int n = a[REC_CICOUNT];
	int layerCount;
	LayerAddr(entity, 0, layerCount);
	if (n > layerCount)
		n = layerCount;
	if (n <= 0)
		return false;

	SaveAllLayers(entity);
	for (int i = 0; i < n; i++)
	{
		Address addr = LayerAddr(entity, i, layerCount);
		if (addr == Address_Null)
			continue;
		int o = REC_CI + i * REC_CISTRIDE;
		int seq = a[o];
		float start = view_as<float>(a[o + 1]);
		float serverStart = start;
		// the client started it when the snapshot with this start time reached it (its clock then is
		// that snapshot's server time), unless the common came back from dormant within 1 s
		int sh = g_iShooter;
		if (sh > 0 && sh < PTX_MAX && i < MAX_CI_LAYERS && g_fTxOvStart[sh][entity * MAX_CI_LAYERS + i] == start)
		{
			float seen = g_fTxOvSeen[sh][entity * MAX_CI_LAYERS + i];
			if (seen > start + 0.0001 && seen <= clock && seen > g_fTxDormant[sh][entity] + 1.0)
				start = seen;
		}
		int order = a[o + 2] & 0xFF;
		bool looping = (a[o + 2] & 0x100) != 0;
		float weight = 0.0, cycle = 0.0;
		if (order < MAX_CI_LAYERS && seq >= 0 && seq < pm.seqInfo.Length)
		{
			float info[SI_SIZE];
			pm.seqInfo.GetArray(seq, info);
			float elapsed = clock - start;
			if (elapsed < 0.0)
				elapsed = 0.0;
			cycle = elapsed * info[SI_RATE];
			if (cycle >= 1.0 && looping)
				cycle -= float(RoundToFloor(cycle));
			if (cycle < 1.0 && info[SI_RATE] > 0.0)
			{
				weight = 1.0;
				float dur = 1.0 / info[SI_RATE], t = cycle * dur;
				if (!(RoundToFloor(info[SI_FLAGS]) & 0x2) && !(looping && elapsed > dur * 0.5))
				{
					if (info[SI_FADEIN] > t)
						weight = t / info[SI_FADEIN];
					else if (info[SI_FADEOUT] > dur - t)
						weight = (dur - t) / info[SI_FADEOUT];
				}
			}
		}
		if (weight > 0.0)
		{
			StoreI(addr, LAYER_FLAGS, LoadI(addr, LAYER_FLAGS) | 1);
			StoreI(addr, LAYER_SEQUENCE, seq);
			StoreI(addr, LAYER_CYCLE, cycle);
			StoreI(addr, LAYER_PREVCYCLE, cycle);
			StoreI(addr, LAYER_WEIGHT, weight);
			StoreI(addr, LAYER_ORDER, i);
		}
		else
		{
			StoreI(addr, LAYER_WEIGHT, 0.0);
			StoreI(addr, LAYER_ORDER, 15);
		}
		if (g_iDebug > 0 && order < MAX_CI_LAYERS)
		{
			char name[SEQ_NAME_LEN];
			SeqName(pm, true, seq, name, sizeof(name));
			char from[48];
			if (start != serverStart)
				FormatEx(from, sizeof(from), " when it reached you; server %.3f", serverStart);
			Dbg(entity, "[posesync] ent %d (common) client overlay %d: %s cycle %.3f weight %.2f (started %.3f%s, client clock %.3f)%s",
				entity, i, name, cycle, weight, start, from, clock, weight > 0.0 ? "" : ", not drawn");
		}
	}
	// Server layers past the ones m_clientAnimatedOverlay carries (Infected::UpdateClientAnimationLayers
	// copies slots 0-5 only) are never drawn by the client: no weight in the rewound skeleton.
	for (int i = n; i < layerCount && i < MAX_LAYERS_SAVED; i++)
	{
		Address addr = LayerAddr(entity, i, layerCount);
		if (addr == Address_Null || view_as<float>(LoadI(addr, LAYER_WEIGHT)) <= 0.0)
			continue;
		StoreI(addr, LAYER_WEIGHT, 0.0);
		StoreI(addr, LAYER_ORDER, 15);
		if (g_iDebug > 0)
			Dbg(entity, "[posesync] ent %d (common): server overlay %d switched off (not sent to the client)", entity, i);
	}
	return true;
}

// Players attached to a rewound player (the Jockey riding it, the survivor it carries) moved with it,
// but their bone cache may still hold the present skeleton: flush it now and again once everything
// is put back.
void FlushFollowers(int parent)
{
	if (g_iOffJockeyAttacker > 0)
		AddFollower(GetEntDataEnt2(parent, g_iOffJockeyAttacker));
	if (g_iOffCarryVictim > 0)
		AddFollower(GetEntDataEnt2(parent, g_iOffCarryVictim));
}

void AddFollower(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;
	FlushBones(client);
	for (int i = 0; i < g_iFollowerCount; i++)
	{
		if (g_iFollowers[i] == client)
			return;
	}
	if (g_iFollowerCount < sizeof(g_iFollowers))
		g_iFollowers[g_iFollowerCount++] = client;
}

void ReleaseFollowers()
{
	for (int i = 0; i < g_iFollowerCount; i++)
	{
		if (IsClientInGame(g_iFollowers[i]))
			FlushBones(g_iFollowers[i]);
	}
	g_iFollowerCount = 0;
}

// Sparse records. BacktrackEntity walks the records from the newest one back and refuses (leaves
// the entity at the present) when one lies more than 64 units (2D) from the one after it, or the
// newest one from the present origin. Records are only made when the simulation time moves, so a
// common infected whose NextBot updates are late, or a player whose commands arrive in a burst, leaves
// such a gap without teleporting; the client interpolates across it. When every gap between the
// newest record and the target time is no faster than SPARSE_MAX_SPEED, the entity has the same
// model throughout, no interpolation reset in between and no parent, it is moved to its recorded
// position (common infected and witches: also yaw) at the target time. Players keep their present
// bounds; their body yaw is set by the rewind already. RestoreEntity puts it back.
bool SparseRewind(int entity, float target)
{
	ArrayList h = g_hHistory[entity];
	if (g_bSparseMoved[entity] || h == null || g_iCount[entity] < 2 || g_iHistRef[entity] != EntIndexToEntRef(entity))
		return false;
	bool player = entity <= MaxClients;
	if (player ? !(IsClientInGame(entity) && IsPlayerAlive(entity)) : GetEntProp(entity, Prop_Data, "m_lifeState") != 0)
		return false;
	if (GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") != -1)
		return false;

	// no parent, so the local origin / angles are the absolute ones and always current
	float now[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", now);
	int size = g_iRingSize, count = g_iCount[entity];
	int idx = g_iHead[entity];
	float dx = now[0] - view_as<float>(h.Get(idx, REC_ORG)), dy = now[1] - view_as<float>(h.Get(idx, REC_ORG + 1));
	if (dx * dx + dy * dy > 4096.0)
		return false;   // it moved without a record: a real jump

	int model = h.Get(idx, REC_MODEL);
	bool gap = false;
	float fastest = 0.0;
	for (int n = 1; n < count; n++)
	{
		// the engine stops at the first record at or before the target time
		if (view_as<float>(h.Get(idx, REC_SIM)) <= target + 0.0001)
			break;
		int older = (idx - 1 + size) % size;
		if (h.Get(older, REC_MODEL) != model || (player && h.Get(idx, REC_RESET) != 0))
			return false;
		float simNew = h.Get(idx, REC_SIM), simOld = h.Get(older, REC_SIM);
		dx = view_as<float>(h.Get(idx, REC_ORG)) - view_as<float>(h.Get(older, REC_ORG));
		dy = view_as<float>(h.Get(idx, REC_ORG + 1)) - view_as<float>(h.Get(older, REC_ORG + 1));
		float d2 = dx * dx + dy * dy;
		if (d2 > 4096.0)
		{
			float dt = simNew - simOld;
			if (dt <= 0.0)
				return false;
			float speed = SquareRoot(d2) / dt;
			if (speed > SPARSE_MAX_SPEED)
				return false;
			if (speed > fastest)
				fastest = speed;
			gap = true;
		}
		idx = older;
	}
	if (!gap)
		return false;

	int a[REC_SIZE], b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, target, a, b, haveB, frac))
		return false;
	// the client holds its newest update when it draws past it
	if (!player && haveB && view_as<float>(b[REC_SIM]) > ClientNewestUpdate(entity, target))
		haveB = false;
	float org[3], ang[3], newAng[3];
	for (int i = 0; i < 3; i++)
	{
		float oa = view_as<float>(a[REC_ORG + i]);
		org[i] = haveB ? oa + (view_as<float>(b[REC_ORG + i]) - oa) * frac : oa;
	}
	GetEntPropVector(entity, Prop_Data, "m_angRotation", ang);
	newAng = ang;
	if (!player && g_iOffAbsRotation > 0)
	{
		float ya = view_as<float>(a[REC_AYAW]);
		newAng[1] = haveB ? ya + AngleDiff(view_as<float>(b[REC_AYAW]), ya) * frac : ya;
	}

	for (int i = 0; i < 3; i++)
	{
		g_fSparseOrg[entity * 3 + i] = now[i];
		g_fSparseAng[entity * 3 + i] = ang[i];
		g_fSparseTo[entity * 3 + i] = org[i];
	}
	g_bSparseMoved[entity] = true;
	g_fSparseSim[entity] = GetEntDataFloat(entity, g_iOffSimTime);
	SDKCall(g_hSetAbsOrigin, entity, org);
	if (!player)
		SDKCall(g_hSetAbsAngles, entity, newAng);
	FlushBones(entity);
	g_iStatSparse++;
	if (g_iDebug > 0)
	{
		float d[3];
		SubtractVectors(org, now, d);
		Dbg(entity, "[posesync] ent %d: the engine refused (records more than 64 units apart, at most %.0f units/s); moved it to the recorded position at %.3f, %.1f units from the present",
			entity, fastest, target, GetVectorLength(d));
	}
	return true;
}

// Per frame: flush debug lines of a rewind outside a player command, end a profile run, send queued
// hitbox beams, run the trace command, and make sure nothing is left rewound.
public void OnGameFrame()
{
	if (g_bDbgPass)
		DbgEndPass(0);     // a rewind outside a player command
	if (g_bProfiling && GetEngineTime() >= g_fProfEnd)
		FinishProfile();
	if (g_hBeams != null && g_iBeamRead < g_hBeams.Length && GetGameTickCount() != g_iBeamTick)
	{
		g_iBeamTick = GetGameTickCount();
		SendQueuedBeams(DRAW_BEAMS_PER_TICK);
	}
	// Safety net: nothing should still be rewound between frames.
	if (g_iAppliedCount > 0)
		RestoreAll();
	if (g_iFollowerCount > 0)
		ReleaseFollowers();
	if (g_iTraceRef != 0 && GetGameTickCount() != g_iTraceLastTick)
	{
		g_iTraceLastTick = GetGameTickCount();
		TraceTick();
	}
}

// Puts back everything rewound in the current lag compensation pass.
void RestoreAll()
{
	for (int i = 0; i < g_iAppliedCount; i++)
	{
		int entity = g_iAppliedList[i];
		if (g_bApplied[entity])
			RestoreEntity(entity);
	}
	g_iAppliedCount = 0;
}

// Puts back one entity's pose parameters, borrowed overlay slots, sequence, cycle and render yaw.
void RestoreEntity(int entity)
{
	g_bApplied[entity] = false;
	if (EntRefToEntIndex(g_iAppliedRef[entity]) != entity)
	{
		ClearRewindState(entity);
		return;
	}
	UndoHold(entity);
	if (g_bSparseMoved[entity])
	{
		// like the engine: present + whatever moved it while it was rewound
		g_bSparseMoved[entity] = false;
		float cur[3], org[3];
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", cur);
		for (int i = 0; i < 3; i++)
			org[i] = g_fSparseOrg[entity * 3 + i] + cur[i] - g_fSparseTo[entity * 3 + i];
		SDKCall(g_hSetAbsOrigin, entity, org);
		if (entity > MaxClients)
		{
			float ang[3];
			for (int i = 0; i < 3; i++)
				ang[i] = g_fSparseAng[entity * 3 + i];
			SDKCall(g_hSetAbsAngles, entity, ang);
		}
		// the engine refused this entity, so FinishLagCompensation does not put its simulation time
		// back; unless the game moved it meanwhile (then the new time is real), the plugin does
		if (FloatAbs(cur[0] - g_fSparseTo[entity * 3 + 0]) < 0.01 && FloatAbs(cur[1] - g_fSparseTo[entity * 3 + 1]) < 0.01
			&& FloatAbs(cur[2] - g_fSparseTo[entity * 3 + 2]) < 0.01)
			SetEntDataFloat(entity, g_iOffSimTime, g_fSparseSim[entity], true);
	}
	// overlay slots: see RestoreTransitionLayers (only slots that still hold the plugin's values)
	RestoreTransitionLayers(entity);
	// a model set during the pass (another plugin's hurt / death hook): the saved pose parameters,
	// sequence and cycle belong to the old model and are not put onto the new one
	if (ModelIndexOf(entity) == g_iAppliedModel[entity])
	{
		for (int i = 0; i < MAXPOSE; i++)
			SetEntDataFloat(entity, g_iOffPose + i * 4, g_fSaved[entity * MAXPOSE + i], false);

		// sequence and cycle: only if they still hold what the plugin wrote. Otherwise either the
		// engine has put its own back already, or the game set new ones during the pass.
		if (g_bCycleSaved[entity] && g_bWroteCycle[entity]
			&& GetEntData(entity, g_iOffCycle) == view_as<int>(g_fWroteCycle[entity])
			&& GetEntData(entity, g_iOffSequence) == g_iWroteCycleSeq[entity])
			SetEntDataFloat(entity, g_iOffCycle, g_fSavedCycle[entity], false);
		if (g_bSeqSaved[entity] && g_bWroteSeq[entity]
			&& GetEntData(entity, g_iOffSequence) == g_iWroteSeq[entity])
			SetEntData(entity, g_iOffSequence, g_iSavedSeq[entity], 4, false);
	}
	g_iTransCount[entity] = 0;
	g_bTransSnap[entity] = false;
	g_bCycleSaved[entity] = false;
	g_bSeqSaved[entity] = false;
	g_bWroteSeq[entity] = false;
	g_bWroteCycle[entity] = false;
	g_bClockMain[entity] = false;
	g_bAnimTarget[entity] = false;

	if (g_bYawSaved[entity])
	{
		g_bYawSaved[entity] = false;
		if (GetAnimState(entity) == g_aSavedAnim[entity])
			StoreToAddress(g_aSavedAnim[entity] + view_as<Address>(g_iOffRenderYaw), g_fSavedYaw[entity], NumberType_Int32, false);
	}

	FlushBones(entity);
}

// Forgets everything a rewind saved for this index, without writing anything back (the entity is gone
// or is not the one that was rewound).
void ClearRewindState(int entity)
{
	g_bApplied[entity] = false;
	g_iTransCount[entity] = 0;
	g_bTransSnap[entity] = false;
	g_bYawSaved[entity] = false;
	g_bSeqSaved[entity] = false;
	g_bCycleSaved[entity] = false;
	g_bWroteSeq[entity] = false;
	g_bWroteCycle[entity] = false;
	g_bClockMain[entity] = false;
	g_bAnimTarget[entity] = false;
	g_bSparseMoved[entity] = false;
	g_bHeld[entity] = false;
}

// The plugin's writes of the main sequence and cycle during a rewind (see RestoreEntity).
void WriteSequence(int entity, int seq)
{
	SetEntData(entity, g_iOffSequence, seq, 4, false);
	g_iWroteSeq[entity] = seq;
	g_bWroteSeq[entity] = true;
}

void WriteCycle(int entity, float cycle)
{
	SetEntDataFloat(entity, g_iOffCycle, cycle, false);
	g_fWroteCycle[entity] = cycle;
	g_iWroteCycleSeq[entity] = GetEntData(entity, g_iOffSequence);
	g_bWroteCycle[entity] = true;
}

void RemoveFromAppliedList(int entity)
{
	for (int i = 0; i < g_iAppliedCount; i++)
	{
		if (g_iAppliedList[i] == entity)
		{
			g_iAppliedList[i] = g_iAppliedList[--g_iAppliedCount];
			return;
		}
	}
}

// Rebuild the skeleton from the animation state just written, and the box the spatial partition
// tests rays against: players and common infected use USE_ROTATION_EXPANDED_SEQUENCE_BOUNDS, so
// that box comes from the current sequence. The engine refreshes it when it sets the sequence
// itself; when the plugin puts in another sequence (the client's), a bullet would otherwise be
// tested against the engine's sequence box and miss hitboxes that lie outside it.
void FlushBones(int entity)
{
	SDKCall(g_hInvalidateBoneCache, entity);
	if (g_hMarkBoundsDirty != null)
	{
		if (g_iOffCollision == -1)
			g_iOffCollision = FindDataMapInfo(entity, "m_Collision");
		if (g_iOffCollision > 0)
		{
			Address ent = GetEntityAddress(entity);
			if (ent != Address_Null)
				SDKCall(g_hMarkBoundsDirty, ent + view_as<Address>(g_iOffCollision));
		}
	}
}

// Pose parameters (and the render yaw) at a time, with the same search as
// CLagCompensationManager::BacktrackEntity:
// walk newest -> oldest, stop at the first record with simtime <= target.
// If the walk runs out, the oldest record is used. Interpolate toward the next
// newer record when record.sim < target < newer.sim.
bool LookupPoses(int entity, float target, float poses[MAXPOSE], float &recSim, float &prevSim, float &frac, float &yaw = 0.0, bool &haveYaw = false)
{
	ArrayList h = g_hHistory[entity];
	int count = g_iCount[entity];
	int size = g_iRingSize;

	int rec[REC_SIZE], prev[REC_SIZE];
	bool havePrev = false;

	// walk on the time cell only, then read the one or two records needed
	int idx = g_iHead[entity];
	for (int n = 1; n < count && view_as<float>(h.Get(idx, REC_SIM)) > target; n++)
	{
		havePrev = true;
		idx = (idx - 1 + size) % size;
	}
	h.GetArray(idx, rec);
	if (havePrev)
		h.GetArray((idx + 1) % size, prev);

	int curModel = ModelIndexOf(entity);
	if (rec[REC_MODEL] != curModel)
		return false;   // different model at that time, pose layout does not match

	recSim = view_as<float>(rec[REC_SIM]);
	prevSim = havePrev ? view_as<float>(prev[REC_SIM]) : recSim;
	frac = 0.0;

	if (havePrev && prev[REC_MODEL] == rec[REC_MODEL] && recSim < target && recSim < prevSim)
		frac = (target - recSim) / (prevSim - recSim);

	haveYaw = (rec[REC_HASYAW] != 0);
	if (haveYaw)
	{
		yaw = view_as<float>(rec[REC_RYAW]);
		if (frac > 0.0 && prev[REC_HASYAW])
		{
			float d = AngleDiff(view_as<float>(prev[REC_RYAW]), yaw);
			yaw = AngleNorm(yaw + d * frac);
		}
	}

	if (frac <= 0.0)
	{
		for (int i = 0; i < MAXPOSE; i++)
			poses[i] = view_as<float>(rec[REC_POSE + i]);
		return true;
	}

	// between two records: looping parameters (a 360 degree yaw) need the model's ranges
	PoseModel pm;
	bool haveModel = GetPoseModel(entity, pm);

	for (int i = 0; i < MAXPOSE; i++)
	{
		float a = view_as<float>(rec[REC_POSE + i]);
		float b = view_as<float>(prev[REC_POSE + i]);
		float loopNorm = 0.0;
		if (haveModel && i < pm.numPose && pm.loop[i] > 0.0 && pm.end[i] != pm.start[i])
			loopNorm = pm.loop[i] / FloatAbs(pm.end[i] - pm.start[i]);
		poses[i] = LerpPose(a, b, frac, loopNorm);
	}
	return true;
}

// The entity's m_nModelIndex (through the resolved offset once recording has started).
int ModelIndexOf(int entity)
{
	if (g_iOffModelIndex != -1)
		return GetEntData(entity, g_iOffModelIndex, 2);
	return GetEntProp(entity, Prop_Data, "m_nModelIndex");
}

// Angle in (-180, 180].
float AngleNorm(float a)
{
	if (a != a || FloatAbs(a) > 1.0e7)
		return 0.0;   // NaN, infinite or nonsense (eye angles come from client commands)
	if (a > 180.0 || a < -180.0)
		a -= 360.0 * float(RoundToFloor((a + 180.0) / 360.0));
	return a;
}

// b - a, the short way around
float AngleDiff(float b, float a)
{
	return AngleNorm(b - a);
}

// The player's CTerrorPlayerAnimState, or null.
Address GetAnimState(int client)
{
	if (g_iOffAnimState == -1 || g_iOffRenderYaw == -1 || client <= 0 || client > MaxClients || !IsClientInGame(client))
		return Address_Null;
	return view_as<Address>(GetEntData(client, g_iOffAnimState));
}

float LoadAnimFloat(Address anim, int off)
{
	return view_as<float>(LoadFromAddress(anim + view_as<Address>(off), NumberType_Int32));
}

// Interpolates a normalized (0..1) pose parameter; loopNorm > 0 for looping ones (a 360 degree yaw).
float LerpPose(float a, float b, float frac, float loopNorm)
{
	if (loopNorm <= 0.0)
		return a + (b - a) * frac;

	// looping parameter (e.g. a 360 degree yaw): take the short way around
	float d = b - a;
	float half = loopNorm * 0.5;
	while (d > half)  d -= loopNorm;
	while (d < -half) d += loopNorm;
	float v = a + d * frac;
	if (v < 0.0) v += loopNorm;
	if (v > 1.0) v -= loopNorm;
	if (v < 0.0) v = 0.0;
	if (v > 1.0) v = 1.0;
	return v;
}

// Debug: how far back the pose parameters were taken from, and which one changed the most.
void DebugRewind(int entity, float target, float recSim, float prevSim, float frac, const float poses[MAXPOSE])
{
	PoseModel pm;
	bool haveModel = GetPoseModel(entity, pm);
	int count = haveModel ? pm.numPose : MAXPOSE;

	float headSim = view_as<float>(g_hHistory[entity].Get(g_iHead[entity], REC_SIM));
	float maxDelta = 0.0;
	int maxIdx = -1;
	for (int i = 0; i < count; i++)
	{
		float d = poses[i] - g_fSaved[entity * MAXPOSE + i];
		if (haveModel)
			d *= (pm.end[i] - pm.start[i]);   // real units
		if (FloatAbs(d) > FloatAbs(maxDelta))
		{
			maxDelta = d;
			maxIdx = i;
		}
	}

	char maxName[POSE_NAME_LEN] = "-";
	if (maxIdx != -1 && haveModel)
		strcopy(maxName, sizeof(maxName), pm.names[maxIdx * POSE_NAME_LEN]);
	else if (maxIdx != -1)
		FormatEx(maxName, sizeof(maxName), "#%d", maxIdx);

	Dbg(entity, "[posesync] ent %d: rewound %.1f ticks behind newest record (target %.3f, newest %.3f, using %.3f / %.3f frac %.2f), biggest change %s %s%.3f",
		entity, (headSim - target) / g_fTick, target, headSim, recSim, prevSim, frac, maxName, maxDelta >= 0.0 ? "+" : "", maxDelta);

	if (g_iDebug >= 2)
	{
		for (int i = 0; i < count; i++)
		{
			if (poses[i] == g_fSaved[entity * MAXPOSE + i])
				continue;
			if (haveModel)
			{
				float range = pm.end[i] - pm.start[i];
				Dbg(entity, "    %-24s now %9.3f  ->  rewound %9.3f",
					pm.names[i * POSE_NAME_LEN], pm.start[i] + g_fSaved[entity * MAXPOSE + i] * range, pm.start[i] + poses[i] * range);
			}
			else
			{
				Dbg(entity, "    #%-2d now %.4f -> rewound %.4f", i, g_fSaved[entity * MAXPOSE + i], poses[i]);
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Model info, read from the .mdl files (with their $includemodel animation files): pose parameter
// names / ranges / looping, sequence names, activities, fade times, cycle rates and hitboxes.
// Parsed once per model and cached.
// ---------------------------------------------------------------------------

// The entity's model info (parsed on first use).
bool GetPoseModel(int entity, PoseModel pm)
{
	int modelIndex = ModelIndexOf(entity);
	if (modelIndex != g_iEntModelIndex[entity])
	{
		g_iEntModelIndex[entity] = modelIndex;
		char path[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", path, sizeof(path));
		g_iEntModelInfo[entity] = (path[0] != '\0') ? FindOrParseModel(path) : -1;
	}

	int idx = g_iEntModelInfo[entity];
	if (idx < 0)
		return false;
	g_Models.GetArray(idx, pm);
	return pm.valid;
}

// Index of a model's info in g_Models, parsing the model the first time.
int FindOrParseModel(const char[] path)
{
	char key[PLATFORM_MAX_PATH];
	strcopy(key, sizeof(key), path);
	StringToLower(key);

	int idx;
	if (g_ModelMap.GetValue(key, idx))
		return idx;

	PoseModel pm;
	pm.seqNames = new ArrayList(ByteCountToCells(SEQ_NAME_LEN));
	pm.seqActs = new ArrayList(ByteCountToCells(64));
	pm.seqInfo = new ArrayList(SI_SIZE);
	pm.hitboxes = new ArrayList(HB_SIZE);
	pm.seqMoveIdx = new ArrayList();
	pm.seqMove = new ArrayList(SM_SIZE);
	StringMap seen = new StringMap();
	pm.valid = AppendModelPoses(path, pm, seen, 0);
	delete seen;

	pm.idxVert = -1;
	pm.idxHoriz = -1;
	pm.idxMoveX = -1;
	pm.idxMoveY = -1;
	pm.idxLeanYaw = -1;
	pm.idxBodyYaw = -1;
	pm.idxBodyPitch = -1;
	pm.idxHeadYaw = -1;
	pm.idxHeadPitch = -1;
	pm.idxLeanPitch = -1;
	for (int i = 0; i < pm.numPose && i < MAXPOSE; i++)
	{
		char n[POSE_NAME_LEN];
		strcopy(n, sizeof(n), pm.names[i * POSE_NAME_LEN]);
		if (StrEqual(n, "vert_vel", false))        pm.idxVert = i;
		else if (StrEqual(n, "horiz_vel", false))  pm.idxHoriz = i;
		else if (StrEqual(n, "move_x", false))     pm.idxMoveX = i;
		else if (StrEqual(n, "move_y", false))     pm.idxMoveY = i;
		else if (StrEqual(n, "lean_yaw", false))   pm.idxLeanYaw = i;
		else if (StrEqual(n, "body_yaw", false))   pm.idxBodyYaw = i;
		else if (StrEqual(n, "body_pitch", false)) pm.idxBodyPitch = i;
		else if (StrEqual(n, "head_yaw", false))   pm.idxHeadYaw = i;
		else if (StrEqual(n, "head_pitch", false)) pm.idxHeadPitch = i;
		else if (StrEqual(n, "lean_pitch", false)) pm.idxLeanPitch = i;
	}
	idx = g_Models.PushArray(pm);
	g_ModelMap.SetValue(key, idx);
	if (!pm.valid)
		LogError("Could not read pose parameters from %s (interpolation falls back to plain lerp).", path);
	return idx;
}

// Reads one .mdl and its includes the way the engine builds a virtual model. Pose parameters mirror
// virtualmodel_t::AppendPoseParameters: own params first, then each $includemodel depth-first;
// duplicates (case-insensitive) widen the range. Sequences keep the engine's numbering (the first
// sequence of a given name wins). Hitboxes and the debug bones come from the main model only.
bool AppendModelPoses(const char[] path, PoseModel pm, StringMap seen, int depth)
{
	if (depth > 8)
		return false;

	File f = OpenFile(path, "rb", true, NULL_STRING);
	if (f == null)
		return false;

	int version = ReadIntAt(f, 4);
	if (ReadIntAt(f, 0) != STUDIO_ID || version < 44 || version > 49)
	{
		delete f;
		return false;
	}

	if (depth == 0 && pm.hitboxes != null)
	{
		// studiohdr_t numhitboxsets 172 / hitboxsetindex 176; mstudiohitboxset_t {nameindex, numhitboxes,
		// hitboxindex}; mstudiobbox_t 68 bytes {bone, group, bbmin[3], bbmax[3], nameindex, unused[8]}
		int numSets = ReadIntAt(f, 172);
		int setIndex = ReadIntAt(f, 176);
		if (numSets > 0)
		{
			int numBoxes = ReadIntAt(f, setIndex + 4);
			int boxIndex = setIndex + ReadIntAt(f, setIndex + 8);
			for (int j = 0; j < numBoxes && j < MAX_DRAW_BOXES; j++)
			{
				int bb = boxIndex + j * 68;
				any hb[HB_SIZE];
				hb[HB_BONE] = ReadIntAt(f, bb);
				hb[HB_GROUP] = ReadIntAt(f, bb + 4);
				for (int a = 0; a < 3; a++)
				{
					hb[HB_MINS + a] = ReadIntAt(f, bb + 8 + a * 4);
					hb[HB_MAXS + a] = ReadIntAt(f, bb + 20 + a * 4);
				}
				pm.hitboxes.PushArray(hb);
			}
		}
	}

	if (depth == 0)
	{
		for (int k = 0; k < NUM_DBG_BONES; k++)
			pm.dbgBone[k] = -1;
		char bname[64];
		int numBones = ReadIntAt(f, 156);
		int boneIndex = ReadIntAt(f, 160);
		for (int j = 0; j < numBones && j < 256; j++)
		{
			int bb = boneIndex + j * 216;
			ReadStringAt(f, bb + ReadIntAt(f, bb), bname, sizeof(bname));
			for (int k = 0; k < NUM_DBG_BONES; k++)
				if (StrEqual(bname, g_sDbgBones[k], false))
					pm.dbgBone[k] = j;
		}
	}

	ArrayList fileSeqs = new ArrayList(2);    // sequences this file added: global index, seqdesc offset
	if (pm.seqNames != null)
	{
		char label[SEQ_NAME_LEN];
		int numSeq = ReadIntAt(f, HDR_NUMLOCALSEQ);
		int seqIndex = ReadIntAt(f, HDR_LOCALSEQINDEX);
		for (int j = 0; j < numSeq; j++)
		{
			int sb = seqIndex + j * SEQDESC_SIZE;
			ReadStringAt(f, sb + ReadIntAt(f, sb + 4), label, sizeof(label));
			// virtualmodel_t::AppendSequences keeps the first sequence of a given name (case-insensitive;
			// 'seen' also holds the pose parameter names, so sequence keys get a prefix)
			char seqKey[SEQ_NAME_LEN + 2];
			FormatEx(seqKey, sizeof(seqKey), "s:%s", label);
			StringToLower(seqKey);
			if (seen.SetValue(seqKey, 1, false))
			{
				pm.seqNames.PushString(label);
				pm.seqMoveIdx.Push(-1);
				int pair[2];
				pair[0] = pm.seqNames.Length - 1;
				pair[1] = sb;
				fileSeqs.PushArray(pair);
				char act[64];
				ReadStringAt(f, sb + ReadIntAt(f, sb + 8), act, sizeof(act));
				pm.seqActs.PushString(act);

				float info[SI_SIZE];
				info[SI_FLAGS] = float(ReadIntAt(f, sb + 12));
				info[SI_FADEIN] = view_as<float>(ReadIntAt(f, sb + 104));
				info[SI_FADEOUT] = view_as<float>(ReadIntAt(f, sb + 108));
				// GetSequenceCycleRate = fps / (frames - 1) of the sequence's first animation
				int animIdx = ReadShortAt(f, sb + ReadIntAt(f, sb + 60));
				int ad = ReadIntAt(f, 184) + animIdx * 100;
				float fps = view_as<float>(ReadIntAt(f, ad + 8));
				int frames = ReadIntAt(f, ad + 16);
				info[SI_RATE] = (frames > 1) ? fps / float(frames - 1) : 0.0;
				int kind = 0;
				// a 3x3 move_x / move_y blend (9 animations in a 3 by 3 grid), or a movement activity
				if ((ReadIntAt(f, sb + 56) == 9 && ReadIntAt(f, sb + 68) == 3 && ReadIntAt(f, sb + 72) == 3) || ActIsMove(act))
					kind |= SK_MOVE;
				if (ActIsEyeLock(act)) kind |= SK_EYELOCK;
				if (ActIsRandomStart(act)) kind |= SK_RANDOM;
				if (StrEqual(act, "ACT_TERROR_HUNTER_POUNCE", false)) kind |= SK_POUNCE;
				if (StrEqual(act, "ACT_TERROR_JOCKEY_RIDE", false)) kind |= SK_JOCKEYRIDE;
				if (ActZeroGroundSpeed(act)) kind |= SK_NOGS;
				// CTerrorPlayerAnimState only computes vert_vel / horiz_vel in these activities
				if (StrEqual(act, "ACT_TERROR_HUNTER_POUNCE", false) || StrEqual(act, "ACT_TERROR_HUNTER_POUNCE_IDLE", false)
					|| StrEqual(act, "ACT_TERROR_IDLE_FALL_FROM_CHARGERHIT", false))
					kind |= SK_VEL;
				info[SI_KIND] = float(kind);
				pm.seqInfo.PushArray(info);
			}
		}
	}

	int numPose = ReadIntAt(f, HDR_NUMPOSEPARAMS);
	int poseIndex = ReadIntAt(f, HDR_POSEPARAMINDEX);
	char name[POSE_NAME_LEN], lower[POSE_NAME_LEN];
	for (int j = 0; j < numPose; j++)
	{
		int b = poseIndex + j * POSEDESC_SIZE;
		int nameOff = ReadIntAt(f, b);
		float start = view_as<float>(ReadIntAt(f, b + 8));
		float end   = view_as<float>(ReadIntAt(f, b + 12));
		float loop  = view_as<float>(ReadIntAt(f, b + 16));
		ReadStringAt(f, b + nameOff, name, sizeof(name));
		strcopy(lower, sizeof(lower), name);
		StringToLower(lower);

		int k;
		if (seen.GetValue(lower, k))
		{
			float s = pm.start[k], e = pm.end[k];
			pm.start[k] = Min4(e, end, s, start);
			pm.end[k]   = Max4(e, end, s, start);
		}
		else if (pm.numPose < MAXPOSE)
		{
			k = pm.numPose++;
			seen.SetValue(lower, k);
			strcopy(pm.names[k * POSE_NAME_LEN], POSE_NAME_LEN, name);
			pm.start[k] = start;
			pm.end[k] = end;
			pm.loop[k] = loop;
		}
	}

	ReadSequenceMovement(f, pm, seen, fileSeqs);
	delete fileSeqs;

	int numInc = ReadIntAt(f, HDR_NUMINCLUDES);
	int incIndex = ReadIntAt(f, HDR_INCLUDEINDEX);
	if (numInc > MAX_INCLUDES)
		numInc = MAX_INCLUDES;

	char includes[MAX_INCLUDES][PLATFORM_MAX_PATH];
	for (int j = 0; j < numInc; j++)
	{
		int g = incIndex + j * MODELGROUP_SIZE;
		int nameOff = ReadIntAt(f, g + 4);
		ReadStringAt(f, g + nameOff, includes[j], PLATFORM_MAX_PATH);
	}
	delete f;

	for (int j = 0; j < numInc; j++)
	{
		if (includes[j][0] != '\0')
			AppendModelPoses(includes[j], pm, seen, depth + 1);
	}
	return true;
}

int ReadShortAt(File f, int pos)
{
	int v = 0;
	f.Seek(pos, SEEK_SET);
	f.ReadInt16(v);
	return v;
}

int ReadIntAt(File f, int pos)
{
	int v = 0;
	f.Seek(pos, SEEK_SET);
	f.ReadInt32(v);
	return v;
}

void ReadStringAt(File f, int pos, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	f.Seek(pos, SEEK_SET);
	f.ReadString(buffer, maxlen, -1);
}

void StringToLower(char[] s)
{
	for (int i = 0; s[i] != '\0'; i++)
		s[i] = CharToLower(s[i]);
}

float Min4(float a, float b, float c, float d)
{
	float m = a;
	if (b < m) m = b;
	if (c < m) m = c;
	if (d < m) m = d;
	return m;
}

float Max4(float a, float b, float c, float d)
{
	float m = a;
	if (b > m) m = b;
	if (c > m) m = c;
	if (d > m) m = d;
	return m;
}

// ---------------------------------------------------------------------------
// Admin commands (diagnostics)
// ---------------------------------------------------------------------------

// sm_posesync_status: settings and counters.
Action Cmd_Status(int client, int args)
{
	int tracked = 0;
	for (int i = 1; i < MAX_ENTS; i++)
	{
		if (g_hHistory[i] != null && g_iCount[i] > 0)
			tracked++;
	}

	ReplyToCommand(client, "[posesync] enabled=%d targets=%d ring=%d records (%.2f s)",
		g_bEnabled, g_iTargets, g_iRingSize, g_iRingSize * g_fTick);
	ReplyToCommand(client, "[posesync] entities with history: %d | records stored: %d | backtracks seen: %d | pose rewinds: %d | no history: %d | engine rejected: %d",
		tracked, g_iStatRecords, g_iStatBacktracks, g_iStatApplied, g_iStatNoHistory, g_iStatEngineRejected);
	ReplyToCommand(client, "[posesync] sequence changes of standing common infected recorded without a new simulation time: %d | moved to where the client drew them: %d (held at the newest update: %d)%s",
		g_iStatIdleSeq, g_iStatClientPos, g_iStatHold, g_bCanMove ? "" : " (no gamedata)");
	ReplyToCommand(client, "[posesync] move blends from the client's velocity estimate: players %d, common infected %d | feet and aim yaw turned like the client after a spawn: %d", g_iStatMoveBlend, g_iStatCommonMove, g_iStatSpawnTurn);
	ReplyToCommand(client, "[posesync] entities kept compensated during a swing: %d%s | ridden survivors rewound: %d%s | gunshots with the animation rewind: %d%s | gaps bridged: %d%s",
		g_iStatSwing, g_bHaveWants ? "" : " (no gamedata)", g_iStatRidden, g_bHaveWants ? "" : " (no gamedata)",
		g_iStatAnimRewind, g_bHaveStart ? "" : " (no gamedata)", g_iStatSparse, g_bCanMove ? "" : " (no gamedata)");
	int infected = 0, live = 0;
	float now = GetGameTime();
	for (int i = MaxClients + 1; i < MAX_ENTS; i++)
	{
		if (!IsValidEntity(i) || !IsInfectedClass(i))
			continue;
		infected++;
		if (g_hHistory[i] != null && g_iCount[i] > 0 && g_iHistRef[i] == EntIndexToEntRef(i)
			&& now - view_as<float>(g_hHistory[i].Get(g_iHead[i], REC_SIM)) < 0.5)
			live++;
	}
	ReplyToCommand(client, "[posesync] common infected / witches: %d, with a lag compensation record from the last 0.5 s: %d", infected, live);
	return Plugin_Handled;
}

// sm_posesync_history: the newest records of an entity (first 8 pose parameters).
Action Cmd_History(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_posesync_history <entindex> [records]");
		return Plugin_Handled;
	}

	int entity = GetCmdArgInt(1);
	int show = (args >= 2) ? GetCmdArgInt(2) : 8;
	if (entity <= 0 || entity >= MAX_ENTS || g_hHistory[entity] == null || g_iCount[entity] == 0)
	{
		ReplyToCommand(client, "[posesync] No history for entity %d.", entity);
		return Plugin_Handled;
	}

	PoseModel pm;
	bool haveModel = GetPoseModel(entity, pm);
	int count = haveModel ? pm.numPose : MAXPOSE;
	if (count > 8) count = 8;   // keep lines readable

	char line[512];
	FormatEx(line, sizeof(line), "%10s", "simtime");
	for (int p = 0; p < count; p++)
	{
		if (haveModel)
			Format(line, sizeof(line), "%s %12.12s", line, pm.names[p * POSE_NAME_LEN]);
		else
			Format(line, sizeof(line), "%s %12d", line, p);
	}
	ReplyToCommand(client, "%s", line);

	int rec[REC_SIZE];
	int idx = g_iHead[entity];
	for (int n = 0; n < g_iCount[entity] && n < show; n++)
	{
		g_hHistory[entity].GetArray(idx, rec);
		FormatEx(line, sizeof(line), "%10.3f", view_as<float>(rec[REC_SIM]));
		for (int p = 0; p < count; p++)
		{
			float norm = view_as<float>(rec[REC_POSE + p]);
			float v = haveModel ? pm.start[p] + norm * (pm.end[p] - pm.start[p]) : norm;
			Format(line, sizeof(line), "%s %12.3f", line, v);
		}
		ReplyToCommand(client, "%s", line);
		idx = (idx - 1 + g_iRingSize) % g_iRingSize;
	}
	return Plugin_Handled;
}

// Index of a sequence label in a model's list, -1 if absent (case-insensitive).
// Sequence label with its activity for debug lines, e.g. "Run (ACT_RUN)".
void SeqLabel(PoseModel pm, int seq, char[] out, int maxlen)
{
	SeqName(pm, true, seq, out, maxlen);
	if (pm.seqActs != null && seq >= 0 && seq < pm.seqActs.Length)
	{
		char act[64];
		pm.seqActs.GetString(seq, act, sizeof(act));
		if (act[0] != '\0')
			Format(out, maxlen, "%s (%s)", out, act);
	}
}

// Sequence kind bits (SK_*), 0 for an unknown sequence.
int SeqKind(PoseModel pm, int seq)
{
	if (pm.seqInfo == null || seq < 0 || seq >= pm.seqInfo.Length)
		return 0;
	return RoundToFloor(view_as<float>(pm.seqInfo.Get(seq, SI_KIND)));
}

// Movement sequence: a 3x3 move_x / move_y blend, or a standing / walking / running activity. The
// client's animstate picks these from the velocity of the position it draws (and plays the blends
// at a rate from that speed), so they run its interpolation behind its clock. Event animations
// (jump, attacks, shoves) start when the networked state arrives and are not delayed.
bool IsMoveSeq(PoseModel pm, int seq)
{
	return (SeqKind(pm, seq) & SK_MOVE) != 0;
}

// Movement activities (the 3x3 blends are recognised by their grid instead).
bool ActIsMove(const char[] act)
{
	static const char moveActs[][] = {
		"ACT_IDLE", "ACT_WALK", "ACT_RUN", "ACT_CROUCHIDLE", "ACT_RUN_CROUCH", "ACT_WALK_CROUCH",
		"ACT_IDLE_INJURED", "ACT_WALK_INJURED", "ACT_RUN_INJURED",
		// The Hunter's leap: the client starts Pounce_01 when it arrives and restarts it its
		// interpolation (lerp in whole ticks) later; from then on it runs like a movement sequence.
		// Before the restart, PrepareClientClockMain keeps the client clock.
		"ACT_TERROR_HUNTER_POUNCE"
	};
	for (int i = 0; i < sizeof(moveActs); i++)
		if (StrEqual(act, moveActs[i], false))
			return true;
	return false;
}

// Sequence label, "?" if unknown.
void SeqName(PoseModel pm, bool haveModel, int seq, char[] out, int maxlen)
{
	if (haveModel && pm.seqNames != null && seq >= 0 && seq < pm.seqNames.Length)
		pm.seqNames.GetString(seq, out, maxlen);
	else
		strcopy(out, maxlen, "?");
}

// Debug: the full server animation state the hitboxes are built from (main sequence, pose
// parameters, a few bone positions, overlay layers).
void DumpAnimState(int entity, const char[] when)
{
	if (!ResolveOffsets(entity))
		return;

	PoseModel pm;
	bool haveModel = GetPoseModel(entity, pm);
	char name[SEQ_NAME_LEN];

	int seq = GetEntProp(entity, Prop_Data, "m_nSequence");
	SeqName(pm, haveModel, seq, name, sizeof(name));
	Dbg(entity, "[posesync] ---- ent %d, %s (tick %d)", entity, when, GetGameTickCount());
	Dbg(entity, "    main: %s (%d) cycle %.3f rate %.2f", name, seq,
		GetEntPropFloat(entity, Prop_Data, "m_flCycle"), GetEntPropFloat(entity, Prop_Data, "m_flPlaybackRate"));

	int count = haveModel ? pm.numPose : MAXPOSE;
	for (int i = 0; i < count; i++)
	{
		float norm = GetEntDataFloat(entity, g_iOffPose + i * 4);
		if (haveModel)
			Dbg(entity, "    pose [%2d] %-14s norm %.3f  real %8.3f", i, pm.names[i * POSE_NAME_LEN], norm, pm.start[i] + norm * (pm.end[i] - pm.start[i]));
		else
			Dbg(entity, "    pose [%2d] norm %.3f", i, norm);
	}

	// Bone positions straight from the server's bone cache (the skeleton the hitboxes are built on),
	// in the entity's local frame (x forward, y left, z up) so they compare with model space.
	if (g_hGetBoneOrigin != null && haveModel)
	{
		float org[3], ang[3], fwd[3], right[3], up[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);
		GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
		Dbg(entity, "    abs angles %.2f %.2f %.2f", ang[0], ang[1], ang[2]);
		Address anim = GetAnimState(entity);
		if (anim != Address_Null)
		{
			// players: SetupBones uses the animstate's render angles (0, render yaw, 0), not the entity angles
			ang[0] = 0.0; ang[1] = LoadAnimFloat(anim, g_iOffRenderYaw); ang[2] = 0.0;
			Dbg(entity, "    animstate: render yaw %.2f (bones use this), eye yaw %.2f, feet yaw %.2f, goal feet yaw %.2f",
				ang[1],
				g_iOffEyeYaw != -1 ? LoadAnimFloat(anim, g_iOffEyeYaw) : 0.0,
				g_iOffFeetYaw != -1 ? LoadAnimFloat(anim, g_iOffFeetYaw) : 0.0,
				g_iOffGoalFeetYaw != -1 ? LoadAnimFloat(anim, g_iOffGoalFeetYaw) : 0.0);
		}
		GetAngleVectors(ang, fwd, right, up);
		for (int k = 0; k < NUM_DBG_BONES; k++)
		{
			if (pm.dbgBone[k] < 0)
				continue;
			float w[3], v[3];
			SDKCall(g_hGetBoneOrigin, entity, w, pm.dbgBone[k]);
			SubtractVectors(w, org, v);
			Dbg(entity, "    bone %-28s local %8.2f %8.2f %8.2f", g_sDbgBones[k],
				GetVectorDotProduct(v, fwd), -GetVectorDotProduct(v, right), GetVectorDotProduct(v, up));
		}
	}

	int off = FindDataMapInfo(entity, "m_AnimOverlay");
	Address base = GetEntityAddress(entity);
	if (off == -1 || base == Address_Null)
		return;

	Address vec = view_as<Address>(view_as<int>(base) + off);
	int elems = LoadFromAddress(vec, NumberType_Int32);
	int n = LoadFromAddress(view_as<Address>(view_as<int>(vec) + 12), NumberType_Int32);
	Dbg(entity, "    overlay layers: %d", n);
	for (int i = 0; elems != 0 && i < n && i < 32; i++)
	{
		int lb = elems + i * LAYER_SIZE;
		int flags = LoadFromAddress(view_as<Address>(lb + LAYER_FLAGS), NumberType_Int32);
		int lseq = LoadFromAddress(view_as<Address>(lb + LAYER_SEQUENCE), NumberType_Int32);
		float lcyc = view_as<float>(LoadFromAddress(view_as<Address>(lb + LAYER_CYCLE), NumberType_Int32));
		float lw = view_as<float>(LoadFromAddress(view_as<Address>(lb + LAYER_WEIGHT), NumberType_Int32));
		int order = LoadFromAddress(view_as<Address>(lb + LAYER_ORDER), NumberType_Int32);
		SeqName(pm, haveModel, lseq, name, sizeof(name));
		Dbg(entity, "    layer [%2d] %-28s (%3d) weight %.2f cycle %.3f order %d flags 0x%x", i, name, lseq, lw, lcyc, order, flags);
	}
}

// sm_posesync_dump: DumpAnimState of an entity's present state.
Action Cmd_Dump(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_posesync_dump <entindex>");
		return Plugin_Handled;
	}
	int entity = GetCmdArgInt(1);
	if (entity <= 0 || entity >= MAX_ENTS || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Data, "m_flPoseParameter"))
	{
		ReplyToCommand(client, "[posesync] %d is not an animating entity.", entity);
		return Plugin_Handled;
	}
	if (!ResolveOffsets(entity))
	{
		ReplyToCommand(client, "[posesync] the entity's datamap offsets could not be found.");
		return Plugin_Handled;
	}
	DumpAnimState(entity, "present state");
	ReplyToCommand(client, "[posesync] Printed to the server console.");
	return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// Shooter
//
// Lag compensation runs inside a player's command. The plugin notes whose command is running so it
// can use that client's interpolation (lerp) and print the debug lines when the command ends.
// ---------------------------------------------------------------------------

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon,
	int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (tickcount > g_iLastCmdTick[client] && tickcount <= GetGameTickCount())
		g_iLastCmdTick[client] = tickcount;
	g_iShooter = client;
	g_bDbgGunFired = false;
	return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons)
{
	// a pass whose FinishLagCompensation never ran: put everything back before the game records it
	UndoButtonPatch(client);
	if (g_iAppliedCount > 0 && g_iPassShooter == client && g_iPassTick == GetGameTickCount())
	{
		RestoreAll();
		ReleaseFollowers();
	}
	DbgEndPass(client);
	g_iShooter = 0;
	g_bDbgGunFired = false;
}

// Shooter's interpolation time. Prefers the engine's own m_fLerpTime (what lag compensation uses);
// falls back to the standard formula from the client's cvars:
//   lerp = max(cl_interp, clamp(cl_interp_ratio) / clamp(cl_updaterate))
float GetShooterLerp(int client, float &cvarLerp)
{
	cvarLerp = 0.0;
	if (client <= 0 || client > MaxClients || !g_bHuman[client])
		return 0.0;
	if (g_iOffLerpTime > 0)
	{
		cvarLerp = GetEntDataFloat(client, g_iOffLerpTime);
		return cvarLerp;
	}

	char buf[32];
	float interp = GetClientInfo(client, "cl_interp", buf, sizeof(buf)) ? StringToFloat(buf) : 0.1;
	float ratio  = GetClientInfo(client, "cl_interp_ratio", buf, sizeof(buf)) ? StringToFloat(buf) : 2.0;
	float rate   = GetClientInfo(client, "cl_updaterate", buf, sizeof(buf)) ? StringToFloat(buf) : 30.0;
	if (g_cvMinRate != null && rate < g_cvMinRate.FloatValue) rate = g_cvMinRate.FloatValue;
	if (g_cvMaxRate != null && rate > g_cvMaxRate.FloatValue) rate = g_cvMaxRate.FloatValue;
	if (g_cvMinRatio != null && g_cvMaxRatio != null && g_cvMinRatio.FloatValue != -1.0)
	{
		if (ratio < g_cvMinRatio.FloatValue) ratio = g_cvMinRatio.FloatValue;
		if (ratio > g_cvMaxRatio.FloatValue) ratio = g_cvMaxRatio.FloatValue;
	}
	if (rate < 1.0) rate = 1.0;
	cvarLerp = (ratio / rate > interp) ? ratio / rate : interp;

	return cvarLerp;
}

// ---------------------------------------------------------------------------
// Client-side sequence transitions
//
// C_BaseAnimating::StandardBlendingRules runs, every frame, after the main sequence:
//   MaintainSequenceTransitions(): for each previous sequence still in the queue,
//     cycle  = its last cycle + (curtime - its last time) * playbackrate * cyclerate (clamped)
//     weight = spline(1 - (curtime - its last time) / min(prev.fadeouttime, new.fadeintime))
//     AccumulatePose(prev sequence, cycle, weight)
// and only then the overlay layers. The server's SetupBones has no such step, so for
// ~0.2 s after every sequence change the client's skeleton is a blend the server never builds.
// The plugin rebuilds the queue from the recorded sequence history and gives it to the server as
// temporary overlay layers (ordered before the real ones) for the duration of the rewind.
// ---------------------------------------------------------------------------

// SimpleSpline, the crossfade weight curve.
float SplineFade(float s)
{
	if (s <= 0.0) return 0.0;
	if (s > 1.0) return 1.0;
	return 3.0 * s * s - 2.0 * s * s * s;
}

// m_AnimOverlay (CUtlVector<CAnimationLayer>): element pointer at +0, count at +12
int LayerBase(int entity, int &count)
{
	count = 0;
	// per entity: an entity that is not a CBaseAnimatingOverlay has no layer vector at all, and
	// another class's offset would read an unrelated member as the element pointer
	int off = (g_iCacheRef[entity] == EntIndexToEntRef(entity)) ? g_iCacheOverlay[entity] : FindDataMapInfo(entity, "m_AnimOverlay");
	if (off <= 0)
		return 0;
	int elems = GetEntData(entity, off);
	count = GetEntData(entity, off + 12);
	if (elems == 0 || count < 0)
		count = 0;
	return elems;
}

// Address of one overlay layer, or null.
Address LayerAddr(int entity, int slot, int &count)
{
	int elems = LayerBase(entity, count);
	if (elems == 0 || slot < 0 || slot >= count)
		return Address_Null;
	return view_as<Address>(elems + slot * LAYER_SIZE);
}

// Raw 32-bit read / write at an offset from an address (layer fields).
int LoadI(Address a, int off) { return LoadFromAddress(view_as<Address>(view_as<int>(a) + off), NumberType_Int32); }
void StoreI(Address a, int off, any v) { StoreToAddress(view_as<Address>(view_as<int>(a) + off), v, NumberType_Int32, false); }

// Rebuilds the client's crossfade queue at the shooter's client clock and puts it in free overlay
// slots. Returns true if any previous sequence still had weight.
bool ApplyTransitions(int entity, float target)
{
	if (!g_bLayersOK)
		return false;
	PoseModel pm;
	if (!GetPoseModel(entity, pm) || pm.seqInfo == null || g_hHistory[entity] == null || g_iCount[entity] < 2)
		return false;

	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	// the shooter's client clock when it fired (its usercmd tick); sequences are not interpolated,
	// the client switches as soon as it receives the change
	float clientTime = ClientClock(entity, target, lerp);

	ArrayList h = g_hHistory[entity];
	int size = g_iRingSize, count = g_iCount[entity];

	// walk newest -> oldest (time, sequence and parity cells only), skipping records newer than the
	// client's clock
	int idx = g_iHead[entity], n = 0;
	for (; n < count; n++)
	{
		if (view_as<float>(h.Get(idx, REC_SIM)) <= clientTime + 0.0001) break;   // same tolerance as FindRecIndex
		idx = (idx - 1 + size) % size;
	}
	if (n >= count) return false;
	// sequence numbers of another model mean nothing in this one's sequence table
	int model = ModelIndexOf(entity);
	if (h.Get(idx, REC_MODEL) != model) return false;
	int curSeq = h.Get(idx, REC_SEQ), curParity = h.Get(idx, REC_PARITY);
	if (g_iDebug > 0 && g_bClockMain[entity] && curSeq != g_iClockSeq[entity])
		Dbg(entity, "[posesync] ent %d: crossfade clock and animation clock disagree on the sequence", entity);

	float runStart = view_as<float>(h.Get(idx, REC_SIM));     // first record of the current run (sequence became current)

	int nTrans = 0;
	int tSeq[MAX_TRANSITIONS];
	float tCycle[MAX_TRANSITIONS], tWeight[MAX_TRANSITIONS];

	for (n++, idx = (idx - 1 + size) % size; n < count && nTrans < MAX_TRANSITIONS; n++, idx = (idx - 1 + size) % size)
	{
		if (h.Get(idx, REC_MODEL) != model)
			break;
		int recSeq = h.Get(idx, REC_SEQ), recParity = h.Get(idx, REC_PARITY);
		if (recSeq == curSeq && recParity == curParity)
		{
			runStart = view_as<float>(h.Get(idx, REC_SIM));
			continue;
		}

		// idx = last record of the previous sequence; it stopped being current at runStart.
		// Players: an interpolation reset on that change (EF_NOINTERP, a no-interp parity bump) makes
		// the client empty its transition queue, like STUDIO_SNAP
		if (entity <= MaxClients && h.Get((idx + 1) % size, REC_RESET) != 0)
			break;
		int prevSeq = recSeq;
		if (curSeq < 0 || curSeq >= pm.seqInfo.Length || prevSeq < 0 || prevSeq >= pm.seqInfo.Length)
			break;
		float ci[SI_SIZE], pi[SI_SIZE];
		pm.seqInfo.GetArray(curSeq, ci);
		pm.seqInfo.GetArray(prevSeq, pi);
		if (RoundToFloor(ci[SI_FLAGS]) & 0x2)    // STUDIO_SNAP clears the queue
			break;
		float fade = pi[SI_FADEOUT] < ci[SI_FADEIN] ? pi[SI_FADEOUT] : ci[SI_FADEIN];
		if (fade <= 0.0)
			break;
		if (clientTime - runStart > 2.0)
			break;    // longer ago than any fade
		float w = SplineFade(1.0 - (clientTime - runStart) / fade);
		float lastSim = view_as<float>(h.Get(idx, REC_SIM));
		if (w < 0.01)
		{
			// this one has faded out; an older one with a longer fade may still be in the queue
			curSeq = prevSeq; curParity = recParity;
			runStart = lastSim;
			continue;
		}

		// the Hunter's leap ran the client's interpolation behind its clock (it restarts it then) and
		// keeps that delay while it fades out
		float prevClock = clientTime;
		if (entity <= MaxClients && (SeqKind(pm, prevSeq) & SK_POUNCE))
			prevClock -= float(RoundToFloor(0.5 + lerp / g_fTick)) * g_fTick;
		float c = view_as<float>(h.Get(idx, REC_CYCLE)) + (prevClock - lastSim) * view_as<float>(h.Get(idx, REC_RATE)) * pi[SI_RATE];
		if (RoundToFloor(pi[SI_FLAGS]) & 0x1)    // STUDIO_LOOPING
			c -= float(RoundToFloor(c));
		else if (c > 1.0) c = 1.0;
		if (c < 0.0) c = 0.0;

		tSeq[nTrans] = prevSeq; tCycle[nTrans] = c; tWeight[nTrans] = w; nTrans++;

		// continue with the run of the previous sequence
		curSeq = prevSeq; curParity = recParity;
		runStart = lastSim;
	}
	if (nTrans == 0)
		return false;

	// Overlay slots: the crossfade goes in free slots with orders 0..n-1 (the client blends the previous
	// sequences right after the main one, before any layer); real active layers move up by n.
	int layerCount;
	LayerAddr(entity, 0, layerCount);
	if (layerCount <= 0 || layerCount > MAX_LAYERS_SAVED)
		return false;

	int slot[MAX_TRANSITIONS], used = 0, maxOrder = -1;
	bool active[MAX_LAYERS_SAVED];
	for (int i = 0; i < layerCount; i++)
	{
		Address a = LayerAddr(entity, i, layerCount);
		active[i] = view_as<float>(LoadI(a, LAYER_WEIGHT)) > 0.0 && (LoadI(a, LAYER_FLAGS) & 1);
		if (active[i])
		{
			int o = LoadI(a, LAYER_ORDER);
			if (o > maxOrder) maxOrder = o;
		}
		else if (used < nTrans)
			slot[used++] = i;
	}
	if (used < nTrans)
		nTrans = used;
	if (maxOrder + nTrans > 14)                      // AccumulateLayers indexes layers by order (< 15)
		nTrans = 14 - maxOrder;
	if (nTrans <= 0)
		return false;

	SaveAllLayers(entity);

	for (int i = 0; i < layerCount; i++)
	{
		Address a = LayerAddr(entity, i, layerCount);
		if (active[i])
			StoreI(a, LAYER_ORDER, LoadI(a, LAYER_ORDER) + nTrans);
		else
			StoreI(a, LAYER_ORDER, 15);                  // MAX_OVERLAYS: keeps idle slots out of the order table
	}
	for (int k = 0; k < nTrans; k++)
	{
		Address a = LayerAddr(entity, slot[k], layerCount);
		StoreI(a, LAYER_FLAGS, 1);                      // ANIM_LAYER_ACTIVE
		StoreI(a, LAYER_SEQUENCE, tSeq[k]);
		StoreI(a, LAYER_CYCLE, tCycle[k]);
		StoreI(a, LAYER_PREVCYCLE, tCycle[k]);                       // m_flPrevCycle
		StoreI(a, LAYER_WEIGHT, tWeight[k]);
		StoreI(a, LAYER_RATE, 0.0);                             // m_flPlaybackRate
		StoreI(a, LAYER_ORDER, nTrans - 1 - k);         // oldest previous sequence first, like the client's queue walk
	}

	if (g_iDebug > 0)
	{
		char name[SEQ_NAME_LEN];
		for (int k = 0; k < nTrans; k++)
		{
			SeqName(pm, true, tSeq[k], name, sizeof(name));
			Dbg(entity, "[posesync] ent %d client transition: %s cycle %.3f weight %.2f (client clock %.3f, lerp %.3f)",
				entity, name, tCycle[k], tWeight[k], clientTime, lerp);
		}
	}
	return true;
}

// Keeps one overlay layer's fields so RestoreTransitionLayers can put them back.
void SaveLayer(int entity, int k, Address a)
{
	g_iTransSaved[entity][k * 7 + 0] = LoadI(a, LAYER_FLAGS);
	g_iTransSaved[entity][k * 7 + 1] = LoadI(a, LAYER_SEQUENCE);
	g_iTransSaved[entity][k * 7 + 2] = LoadI(a, LAYER_CYCLE);
	g_iTransSaved[entity][k * 7 + 3] = LoadI(a, LAYER_PREVCYCLE);
	g_iTransSaved[entity][k * 7 + 4] = LoadI(a, LAYER_WEIGHT);
	g_iTransSaved[entity][k * 7 + 5] = LoadI(a, LAYER_RATE);
	g_iTransSaved[entity][k * 7 + 6] = LoadI(a, LAYER_ORDER);
}

// After the plugin's layer writes: what each saved slot holds now, so the restore can tell a slot
// the game changed during the pass (a new gesture) from one that still holds the plugin's values.
void SnapshotWrittenLayers(int entity)
{
	int n = g_iTransCount[entity], layerCount;
	for (int k = 0; k < n && k < 16; k++)
	{
		Address a = LayerAddr(entity, k, layerCount);
		if (a == Address_Null)
			continue;
		g_iTransWritten[entity][k * 7 + 0] = LoadI(a, LAYER_FLAGS);
		g_iTransWritten[entity][k * 7 + 1] = LoadI(a, LAYER_SEQUENCE);
		g_iTransWritten[entity][k * 7 + 2] = LoadI(a, LAYER_CYCLE);
		g_iTransWritten[entity][k * 7 + 3] = LoadI(a, LAYER_PREVCYCLE);
		g_iTransWritten[entity][k * 7 + 4] = LoadI(a, LAYER_WEIGHT);
		g_iTransWritten[entity][k * 7 + 5] = LoadI(a, LAYER_RATE);
		g_iTransWritten[entity][k * 7 + 6] = LoadI(a, LAYER_ORDER);
	}
	g_bTransSnap[entity] = true;
}

// Puts back the overlay layers changed by ApplyTransitions / ApplyClientClockLayers. A slot that no
// longer holds what the plugin wrote was changed by the game during the pass and is left as it is.
void RestoreTransitionLayers(int entity)
{
	int n = g_iTransCount[entity];
	bool snap = g_bTransSnap[entity];
	g_iTransCount[entity] = 0;
	g_bTransSnap[entity] = false;
	if (n <= 0)
		return;
	// The slots belong to the entity, not the model: after a model change during the pass, a slot
	// that still holds exactly what the plugin wrote (the snapshot) is put back too, or the borrowed
	// crossfade slots (playback rate 0) would stay active for good. Without a snapshot only the
	// same model is restored.
	if (!snap && ModelIndexOf(entity) != g_iAppliedModel[entity])
		return;
	int layerCount;
	for (int k = 0; k < n; k++)
	{
		Address a = LayerAddr(entity, k, layerCount);
		if (a == Address_Null)
			continue;
		if (snap && k < 16 && (LoadI(a, LAYER_FLAGS) != g_iTransWritten[entity][k * 7 + 0]
			|| LoadI(a, LAYER_SEQUENCE) != g_iTransWritten[entity][k * 7 + 1]
			|| LoadI(a, LAYER_CYCLE) != g_iTransWritten[entity][k * 7 + 2]
			|| LoadI(a, LAYER_WEIGHT) != g_iTransWritten[entity][k * 7 + 4]
			|| LoadI(a, LAYER_ORDER) != g_iTransWritten[entity][k * 7 + 6]))
			continue;
		StoreI(a, LAYER_FLAGS, g_iTransSaved[entity][k * 7 + 0]);
		StoreI(a, LAYER_SEQUENCE, g_iTransSaved[entity][k * 7 + 1]);
		StoreI(a, LAYER_CYCLE, g_iTransSaved[entity][k * 7 + 2]);
		StoreI(a, LAYER_PREVCYCLE, g_iTransSaved[entity][k * 7 + 3]);
		StoreI(a, LAYER_WEIGHT, g_iTransSaved[entity][k * 7 + 4]);
		StoreI(a, LAYER_RATE, g_iTransSaved[entity][k * 7 + 5]);
		StoreI(a, LAYER_ORDER, g_iTransSaved[entity][k * 7 + 6]);
	}
}

bool IsInfectedClass(int entity)
{
	char cls[32];
	GetEntityClassname(entity, cls, sizeof(cls));
	return StrEqual(cls, "infected") || StrEqual(cls, "witch");
}

// ---------------------------------------------------------------------------
// Developer-only debug cvars (sv_showanimstate, cl_showanimstate, ...): retail builds hide them;
// sm_posesync_unhide makes them usable. On a listen server this also covers the cl_ ones.
// ---------------------------------------------------------------------------

void UnhideDevCvars(bool verbose, int client = 0)
{
	for (int i = 0; i < sizeof(g_sDevCvars); i++)
	{
		ConVar cv = FindConVar(g_sDevCvars[i]);
		if (cv == null)
		{
			if (verbose)
				ReplyToCommand(client, "[posesync] %s: not found (client cvars only exist on a listen server)", g_sDevCvars[i]);
			continue;
		}
		int flags = cv.Flags;
		if (flags & (FCVAR_DEVELOPMENTONLY | FCVAR_HIDDEN))
		{
			cv.Flags = flags & ~(FCVAR_DEVELOPMENTONLY | FCVAR_HIDDEN);
			if (verbose)
				ReplyToCommand(client, "[posesync] %s: unhidden", g_sDevCvars[i]);
		}
		else if (verbose)
			ReplyToCommand(client, "[posesync] %s: already visible", g_sDevCvars[i]);
	}
}

public Action Cmd_Unhide(int client, int args)
{
	UnhideDevCvars(true, client);
	return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// When the engine does not rewind
//
// BacktrackEntity walks the records newest -> oldest and gives up when a record is not alive or
// lies more than 64 units from the previous position (starting with the current origin). Records
// are only made when m_flSimulationTime advances, so an entity that moves without updating its
// simulation time "teleports" as far as lag compensation is concerned. It also returns false when
// there is nothing to move, which is not a refusal: the animation frame still has to be set.
// ---------------------------------------------------------------------------

// The engine had nothing to move: alive, its recorded position at the target time is within 1 unit
// of the present origin, and none of the engine's teleport tests (a step of more than 64 units, 2D,
// from the present origin to the newest record and between the records back to the target time)
// would have refused it. Only then is "not rewound" the in-place case and not a refusal.
bool NothingToMove(int entity, float target)
{
	if (g_hHistory[entity] == null || g_iCount[entity] == 0)
		return false;
	bool alive = (entity <= MaxClients) ? (IsClientInGame(entity) && IsPlayerAlive(entity)) : (GetEntProp(entity, Prop_Data, "m_lifeState") == 0);
	if (!alive)
		return false;
	ArrayList h = g_hHistory[entity];
	float org[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);

	int size = g_iRingSize, count = g_iCount[entity];
	int idx = g_iHead[entity];
	float px = org[0], py = org[1];
	for (int n = 0; n < count; n++)
	{
		float rx = view_as<float>(h.Get(idx, REC_ORG)), ry = view_as<float>(h.Get(idx, REC_ORG + 1));
		if ((rx - px) * (rx - px) + (ry - py) * (ry - py) > 4096.0)
			return false;
		if (view_as<float>(h.Get(idx, REC_SIM)) <= target + 0.0001)
			break;
		px = rx;
		py = ry;
		idx = (idx - 1 + size) % size;
	}

	int a[REC_SIZE], b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, target, a, b, haveB, frac))
		return false;
	float d2 = 0.0;
	for (int i = 0; i < 3; i++)
	{
		float oa = view_as<float>(a[REC_ORG + i]);
		float at = haveB ? oa + (view_as<float>(b[REC_ORG + i]) - oa) * frac : oa;
		d2 += (org[i] - at) * (org[i] - at);
	}
	return d2 <= 1.0;
}

// Debug: why the engine left an entity at the present.
void RefusalReason(int entity, float target, char[] out, int maxlen)
{
	if (g_hHistory[entity] == null || g_iCount[entity] == 0)
	{
		strcopy(out, maxlen, "no history");
		return;
	}
	int rec[REC_SIZE];
	g_hHistory[entity].GetArray(g_iHead[entity], rec);
	float org[3], d[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);
	d[0] = org[0] - view_as<float>(rec[REC_ORG]);
	d[1] = org[1] - view_as<float>(rec[REC_ORG + 1]);
	d[2] = org[2] - view_as<float>(rec[REC_ORG + 2]);
	float dist = GetVectorLength(d);
	float stale = (GetGameTime() - view_as<float>(rec[REC_SIM])) / g_fTick;
	bool alive = (entity <= MaxClients) ? IsPlayerAlive(entity) : (GetEntProp(entity, Prop_Data, "m_lifeState") == 0);
	FormatEx(out, maxlen, "%s; newest record is %.1f ticks old (%.1f ticks before the target time) and %.1f units from the current origin%s",
		alive ? "alive" : "dead", stale, (target - view_as<float>(rec[REC_SIM])) / g_fTick, dist, dist > 64.0 ? " (> 64, counts as a teleport)" : "");
}

// ---------------------------------------------------------------------------
// sm_posesync_trace: one line per server tick about one entity (simulation time, origin, velocity,
// no-interp state, sequence, cycle, body yaw), to compare with cl_showanimstate frame by frame.
// ---------------------------------------------------------------------------

// sm_posesync_trace <ent> [seconds]: start (or, with 0, stop) a trace.
public Action Cmd_Trace(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_posesync_trace <entindex> [seconds]   (sm_posesync_trace 0 stops)");
		return Plugin_Handled;
	}
	char buf[16];
	GetCmdArg(1, buf, sizeof(buf));
	int ent = StringToInt(buf);
	float secs = 5.0;
	if (args >= 2)
	{
		GetCmdArg(2, buf, sizeof(buf));
		secs = StringToFloat(buf);
	}
	if (ent <= 0)
	{
		g_iTraceRef = 0;
		ReplyToCommand(client, "[posesync] trace stopped");
		return Plugin_Handled;
	}
	if (ent >= MAX_ENTS || !IsValidEntity(ent) || !HasEntProp(ent, Prop_Data, "m_flPoseParameter"))
	{
		ReplyToCommand(client, "[posesync] %d is not an animating entity.", ent);
		return Plugin_Handled;
	}
	g_iTraceRef = EntIndexToEntRef(ent);
	g_fTraceEnd = GetGameTime() + secs;
	g_fTraceLastSim = 0.0;
	g_iTraceLastParity = -1;
	if (client > 0)
		ReplyToCommand(client, "[posesync] tracing ent %d for %.1f s, printed to the server console.", ent, secs);
	PrintToServer("[trace] ent %d for %.1f s. columns: tick | sim time (ticks behind now, + = advanced this tick) | origin | speed | nointerp | sequence cycle | body yaw / eye yaw", ent, secs);
	return Plugin_Handled;
}

// One trace line (from OnGameFrame, once per tick).
void TraceTick()
{
	int ent = EntRefToEntIndex(g_iTraceRef);
	if (ent <= 0 || GetGameTime() > g_fTraceEnd)
	{
		g_iTraceRef = 0;
		PrintToServer("[trace] done");
		return;
	}
	float now = GetGameTime(), tick = g_fTick;
	float sim = GetEntPropFloat(ent, Prop_Data, "m_flSimulationTime");
	float org[3], vel[3];
	GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", org);
	GetEntPropVector(ent, Prop_Data, "m_vecAbsVelocity", vel);
	int effects = GetEntProp(ent, Prop_Data, "m_fEffects");
	char noi[24] = "-";
	if (ent <= MaxClients && HasEntProp(ent, Prop_Send, "m_ubEFNoInterpParity"))
	{
		int par = GetEntProp(ent, Prop_Send, "m_ubEFNoInterpParity");
		FormatEx(noi, sizeof(noi), "%s%s", (effects & 8) ? "EF " : "", (g_iTraceLastParity != -1 && par != g_iTraceLastParity) ? "PARITY-BUMP" : "");
		g_iTraceLastParity = par;
	}
	else if (effects & 8)
		strcopy(noi, sizeof(noi), "EF");
	PoseModel pm;
	bool haveModel = GetPoseModel(ent, pm);
	char seqName[SEQ_NAME_LEN];
	int seq = GetEntProp(ent, Prop_Data, "m_nSequence");
	SeqName(pm, haveModel, seq, seqName, sizeof(seqName));
	char yaw[48] = "";
	Address anim = GetAnimState(ent);
	if (anim != Address_Null)
		FormatEx(yaw, sizeof(yaw), "%.1f / %.1f", LoadAnimFloat(anim, g_iOffRenderYaw), g_iOffEyeYaw != -1 ? LoadAnimFloat(anim, g_iOffEyeYaw) : 0.0);
	PrintToServer("[trace] %d | %.3f (%.1f%s) | %.2f %.2f %.2f | %.1f | %s | %s %.3f | %s",
		GetGameTickCount(), sim, (now - sim) / tick, sim > g_fTraceLastSim ? " +" : "",
		org[0], org[1], org[2], SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]), noi,
		seqName, GetEntPropFloat(ent, Prop_Data, "m_flCycle"), yaw);
	g_fTraceLastSim = sim;
}

// ---------------------------------------------------------------------------
// Interpolation reset window
//
// When the client gets a player new (a spawn in view, a materialized special infected, a player back
// in its PVS) or the player gets EF_NOINTERP (a teleport), it throws its position history away. For
// its extrapolation limit after that (cl_extrapolate_amount, 0.25 s; measured as about 7 ticks at
// 30 tick and 0.25 s at 100 tick) it draws the newest position without its usual delay and its
// speed estimate (EstimateAbsVelocity) is 0. The window runs from the reset whether or not the
// player moves: a Jockey that stood 0.23 s after spawning and then ran had a 0 speed estimate on
// the client for only the first 4 frames of the run (anim_showstate).
// Its animstate therefore keeps move_x / move_y at 0. The server never does that, so for that
// window the plugin copies it into the rewound pose.
// ---------------------------------------------------------------------------

// Is the shooter's client inside a reset window for this player? display = the newest record the
// client can have drawn, resetSim = the reset.
bool FindResetWindow(int entity, float target, float &display, float &resetSim)
{
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] < 2)
		return false;

	float tick = g_fTick;
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float clock = target + lerp;
	int size = g_iRingSize, count = g_iCount[entity];

	// newest record the client can have drawn
	int idx = g_iHead[entity], n = 0;
	for (; n < count; n++)
	{
		if (view_as<float>(h.Get(idx, REC_SIM)) <= clock + 0.001)
			break;
		idx = (idx - 1 + size) % size;
	}
	if (n >= count)
		return false;
	display = view_as<float>(h.Get(idx, REC_SIM));

	// counted in the time the client draws: the target, not the newest record
	float window = RESET_WINDOW_TIME;
	bool created;
	if (ClientResetIndex(entity, display, window + lerp + tick, resetSim, created) == -1)
		return false;
	return target - resetSim <= window;
}

// The record at or before t at which the shooter's client last reset its interpolation of a player,
// at most maxAgo before t: a reset record (EF_NOINTERP, no-interp parity bump, the first record of a
// life) or the first record it was sent after the player entered its snapshots. -1 = none.
// created: that entry was the first since the player or the shooter connected, so the client made
// the entity then (its eased pose parameters start at the bottom of their range, see ClientSpawnTurn).
int ClientResetIndex(int entity, float t, float maxAgo, float &resetSim, bool &created)
{
	resetSim = -1.0;
	created = false;
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] == 0 || entity > MaxClients)
		return -1;
	int size = g_iRingSize, count = g_iCount[entity];
	int now = GetGameTickCount();
	bool flagged = g_fResetSim[entity] >= 0.0 && g_fResetSim[entity] <= t + 0.0001 && t - g_fResetSim[entity] <= maxAgo + 0.0001;
	int sh = g_iShooter;
	bool entry = sh > 0 && sh < PTX_MAX && entity < PTX_MAX && g_iPlTxCount[sh][entity] > 0
		&& float(now - g_iPlTxEnter[sh][entity]) * g_fTick <= maxAgo + 1.0;
	int enterRec = entry ? g_iPlTxEnter[sh][entity] - g_iTxRecGap : 0;

	int best = -1;
	int idx = g_iHead[entity];
	for (int k = 0; k < count; k++, idx = (idx - 1 + size) % size)
	{
		float sim = view_as<float>(h.Get(idx, REC_SIM));
		// the newest record made by the tick of the entering snapshot
		bool isEntry = entry && h.Get(idx, REC_TICK) <= enterRec;
		if (sim > t + 0.0001)
		{
			if (isEntry)
				entry = false;      // it entered after t
			continue;
		}
		if (t - sim > maxAgo + 0.0001)
			break;
		if (isEntry || (flagged && h.Get(idx, REC_RESET)))
		{
			best = idx;
			created = isEntry && g_bPlTxNew[sh][entity];
			break;
		}
		if (!entry && !flagged)
			break;
	}
	if (best != -1)
	{
		resetSim = view_as<float>(h.Get(best, REC_SIM));
		// a bot is sent to the shooter from when it connects, which can be before the first record of
		// its life: that first record is then where the client made it
		if (!created && sh > 0 && sh < PTX_MAX && entity < PTX_MAX && g_bPlTxNew[sh][entity] && g_iPlTxCount[sh][entity] > 0)
		{
			int rt = h.Get(best, REC_TICK);
			int et = g_iPlTxEnter[sh][entity];
			if (et <= rt + 1 && float(rt - et) * g_fTick <= 0.5)
				created = true;
		}
	}
	return best;
}

// Neutral move blend, as the client draws it in the window (its speed estimate is 0). The frame is
// the same as for the rest of the run: taking the slower centre animation's cycle for the window
// put the start of a run behind the client in game.
void ApplyResetWindow(int entity, float poses[MAXPOSE], float display, float resetSim)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return;
	for (int k = 0; k < 2; k++)
	{
		int i = (k == 0) ? pm.idxMoveX : pm.idxMoveY;
		if (i == -1)
			continue;
		float range = pm.end[i] - pm.start[i];
		if (range != 0.0)
			poses[i] = (0.0 - pm.start[i]) / range;
	}
	if (g_iDebug > 0)
		Dbg(entity, "[posesync] ent %d: %.1f ticks after an interpolation reset, client speed estimate is 0: neutral move blend",
			entity, (display - resetSim) / g_fTick);
}


// ---------------------------------------------------------------------------
// Eye-driven values
//
// C_TerrorPlayer interpolates other players' m_angEyeAngles like their origin (client.dll
// registers an interpolated variable for it, "C_CSPlayer::m_iv_angEyeAngles", 0x10224fe9), and
// UpdateClientSideAnimation (0x10223019) gives that value to the animstate. So other players aim
// and turn with their eye angles at the time the client draws them.
//
// body_pitch: the client's animstate eases body_pitch to the eye pitch it is given, the networked
// m_angEyeAngles[0]. The server's own body_pitch follows its animstate's eye pitch, which is not
// always the networked one, so body_pitch is rebuilt from the recorded networked pitch.
//
// Eye lock: the client's CTerrorPlayerAnimState::Update (0x102822d0) stops taking new eye angles
// while ShouldLockEyeYaw (0x1027eb30) is true, which is while its main activity is a shove stagger,
// a pounce knock-off, a Charger pummel / pound (both sides) or a wall / ground slam. The body keeps
// the aim and turn it had when that started, while the server's keeps following the eyes. The run
// of those activities is found in the records at the client clock (the client starts them when they
// arrive), and the eye values are taken from the time the client drew when it started.
// ---------------------------------------------------------------------------

// Eye lock snapshot: when a player's main sequence becomes an eye-lock activity, the eye angles and
// render yaw of the records just before it are kept, because a lock (a long stagger at 30 tick, a
// pummel) can outlast the lag compensation history while the client still holds those values.
#define LOCKSNAP 48
#define LOCKSNAP_TIME 0.5
float g_fLockSnapStart[PTX_MAX];                 // sim time of the first record of the lock run, -1 = none
int   g_iLockSnapModel[PTX_MAX];
int   g_iLockSnapN[PTX_MAX];
float g_fLockSnap[PTX_MAX][LOCKSNAP * 4];        // per entry (entry * 4 +): sim, eye pitch, eye yaw, render yaw (oldest first)
bool  g_bLockSnapYaw[PTX_MAX][LOCKSNAP];
bool  g_bLockFromSnap;                           // FindEyeLockStart found the start only in the snapshot

// How the animstate turns the feet toward their goal (CTerrorPlayerAnimState::ConvergeAngles,
// server_srv.so 0x503020, the same code in client.dll): each frame by
//   min(mp_feetyawrate * r * clamp(gap / 45, 0.01, 1), mp_feetmaxyawrate * r) * frame time
// with mp_feetyawrate 180, mp_feetmaxyawrate 100 and r = GetTurnRate (0x503bc0): 2 while the
// animstate's speed is over 0.5, 1 below it. So 100 r degrees/s down to a 25 degree gap, then the
// gap shrinks by e^(-4 r) per second. Seen with anim_showstate: e^-8 per second during a shove
// stagger, and 200 degrees/s while a spawned Jockey turned to its run direction.
#define FEET_YAW_RATE     180.0
#define FEET_MAX_YAW_RATE 100.0
#define FEET_TURN_MOVING  2.0

// Called before a player's record is stored: on the start of an eye-lock run, keep the recent eye
// angles and render yaw.
void NoteLockStart(int entity, const int rec[REC_SIZE])
{
	if (entity >= PTX_MAX || g_iCount[entity] == 0)
		return;
	if (g_iHeadSeq[entity] == rec[REC_SEQ])
		return;
	ArrayList h = g_hHistory[entity];
	int head = g_iHead[entity];
	PoseModel pm;
	if (!GetPoseModel(entity, pm) || !IsEyeLockAct(pm, rec[REC_SEQ]) || IsEyeLockAct(pm, g_iHeadSeq[entity]))
		return;
	float sim = view_as<float>(rec[REC_SIM]);
	int size = g_iRingSize, count = g_iCount[entity];
	int n = 0, idx = head;
	while (n < LOCKSNAP - 1 && n < count && sim - view_as<float>(h.Get(idx, REC_SIM)) <= LOCKSNAP_TIME)
	{
		n++;
		idx = (idx - 1 + size) % size;
	}
	// oldest first, then the new record itself
	idx = (head - n + 1 + size) % size;
	for (int k = 0; k < n; k++, idx = (idx + 1) % size)
	{
		g_fLockSnap[entity][k * 4 + 0] = view_as<float>(h.Get(idx, REC_SIM));
		g_fLockSnap[entity][k * 4 + 1] = view_as<float>(h.Get(idx, REC_EYEP));
		g_fLockSnap[entity][k * 4 + 2] = view_as<float>(h.Get(idx, REC_EYEY));
		g_fLockSnap[entity][k * 4 + 3] = view_as<float>(h.Get(idx, REC_RYAW));
		g_bLockSnapYaw[entity][k] = h.Get(idx, REC_HASYAW) != 0 && h.Get(idx, REC_HASEYE) != 0;
	}
	g_fLockSnap[entity][n * 4 + 0] = sim;
	g_fLockSnap[entity][n * 4 + 1] = view_as<float>(rec[REC_EYEP]);
	g_fLockSnap[entity][n * 4 + 2] = view_as<float>(rec[REC_EYEY]);
	g_fLockSnap[entity][n * 4 + 3] = view_as<float>(rec[REC_RYAW]);
	g_bLockSnapYaw[entity][n] = rec[REC_HASYAW] != 0 && rec[REC_HASEYE] != 0;
	g_iLockSnapN[entity] = n + 1;
	g_fLockSnapStart[entity] = sim;
	g_iLockSnapModel[entity] = rec[REC_MODEL];
}

// Eye pitch / yaw and render yaw at t from the lock snapshot.
bool LockSnapAt(int entity, float t, float &pitch, float &yaw, float &ryaw)
{
	if (entity >= PTX_MAX || g_iLockSnapN[entity] == 0)
		return false;
	int n = g_iLockSnapN[entity], k = 0;
	while (k < n - 1 && g_fLockSnap[entity][(k + 1) * 4 + 0] <= t)
		k++;
	if (!g_bLockSnapYaw[entity][k])
		return false;
	pitch = AngleNorm(g_fLockSnap[entity][k * 4 + 1]);
	yaw = AngleNorm(g_fLockSnap[entity][k * 4 + 2]);
	ryaw = AngleNorm(g_fLockSnap[entity][k * 4 + 3]);
	if (k < n - 1 && g_bLockSnapYaw[entity][k + 1] && t > g_fLockSnap[entity][k * 4 + 0])
	{
		float f = (t - g_fLockSnap[entity][k * 4 + 0]) / (g_fLockSnap[entity][(k + 1) * 4 + 0] - g_fLockSnap[entity][k * 4 + 0]);
		if (f > 1.0) f = 1.0;
		pitch += AngleDiff(AngleNorm(g_fLockSnap[entity][(k + 1) * 4 + 1]), pitch) * f;
		yaw = AngleNorm(yaw + AngleDiff(AngleNorm(g_fLockSnap[entity][(k + 1) * 4 + 2]), yaw) * f);
		ryaw = AngleNorm(ryaw + AngleDiff(AngleNorm(g_fLockSnap[entity][(k + 1) * 4 + 3]), ryaw) * f);
	}
	return true;
}

// The client's feet yaw after 'elapsed' seconds of turning from 'feet' toward 'goal' while moving
// (r = 2; a staggered player is pushed), in server ticks.
float ConvergeFeet(float feet, float goal, float elapsed)
{
	goal = AngleNorm(goal);
	for (float t = 0.0; t < elapsed && feet != goal; t += g_fTick)
		feet = FeetStep(feet, goal, goal, FEET_TURN_MOVING, (elapsed - t < g_fTick) ? elapsed - t : g_fTick);
	return feet;
}

// ---------------------------------------------------------------------------
// Feet and aim yaw after an interpolation reset (spawn)
//
// The animstate's feet goal and turn rate, and the easing of body_yaw / head_yaw, depend on its
// speed (server_srv.so CTerrorPlayerAnimState::UpdateFootYaw 0x504260, ComputePoseParam_AimYaw
// 0x5004f0, the same code in client.dll):
//   goal: when speed > 0.5 and speed > 0.9 * GetCurrentMaxGroundSpeed, the velocity yaw (+180 when
//         that is more than 100 degrees from the eyes); otherwise it stays. Then it is kept within
//         45 degrees of the eye yaw (90 for survivors).
//   feet: ConvergeAngles toward the goal, r = 2 when speed > 0.5, else 1 (see FEET_YAW_RATE).
//   aim:  T = eye yaw - feet yaw (folded past +-90). body_yaw += 2 * f * dt * (T - body_yaw) with
//         f = 5 when speed > 0.5, else 3; head_yaw += 20 * dt * (T - body_yaw - head_yaw).
// The client's speed is its estimate, which is 0 for the reset window (RESET_WINDOW_TIME) after it
// gets a spawned player. So in the window its feet turn at half the server's rate and its body_yaw
// eases more slowly, and when the window ends the jump in its estimate (seen as 1150 u/s with
// anim_showstate) sets the feet goal to the run direction at once, while the server waits for 90%
// of the ground speed. The plugin runs this model for both sides over the records since the reset
// and adds the client's difference to the server's recorded feet yaw, body_yaw and head_yaw. Away
// from a window both sides get the same inputs, so the difference is 0.
// ---------------------------------------------------------------------------

#define SPAWN_TURN_TIME 2.0     // how long after a reset the difference is worked out

float FeetGoal(float goal, float eye, bool fast, float velYaw, float lookRange)
{
	if (fast)
	{
		float d = AngleDiff(velYaw, eye);
		goal = (d >= -100.0 && d <= 100.0) ? velYaw : AngleNorm(velYaw + 180.0);
	}
	float delta = AngleDiff(goal, eye);
	if (FloatAbs(delta) > lookRange)
		goal = AngleNorm(eye + (delta < 0.0 ? -lookRange : lookRange));
	return goal;
}

float FeetStep(float cur, float goal, float eye, float r, float dt)
{
	float d = AngleDiff(goal, cur);
	float ad = FloatAbs(d);
	if (ad < 0.0001)
		return cur;
	float dir = (ad > 90.0) ? AngleDiff(eye, cur) : d;
	float fac = 1.0;
	if (ad < 45.0)
	{
		fac = ad / 45.0;
		if (fac < 0.01) fac = 0.01;
	}
	float step = fac * FEET_YAW_RATE * r;
	if (step > FEET_MAX_YAW_RATE * r)
		step = FEET_MAX_YAW_RATE * r;
	step *= dt;
	if (step > ad)
		return AngleNorm(goal);
	return AngleNorm(cur + (dir > 0.0 ? step : -step));
}

void AimStep(float &body, float &head, float eye, float feet, bool moving, float dt, PoseModel pm)
{
	float T = AngleDiff(eye, feet);
	if (T > 90.0) T = 180.0 - T;
	else if (T < -90.0) T = -180.0 - T;
	float g = T - body;
	float s = 2.0 * (moving ? 5.0 : 3.0) * dt * g;
	if (FloatAbs(g) < FloatAbs(s)) s = g;
	float nb = body + s;
	float g2 = T - nb - head;
	float s2 = 20.0 * dt * g2;
	if (FloatAbs(g2) < FloatAbs(s2)) s2 = g2;
	head += s2;
	body = nb;
	if (pm.idxBodyYaw != -1 && pm.end[pm.idxBodyYaw] != pm.start[pm.idxBodyYaw])
		body = ClampRaw(pm, pm.idxBodyYaw, body);
	if (pm.idxHeadYaw != -1 && pm.end[pm.idxHeadYaw] != pm.start[pm.idxHeadYaw])
		head = ClampRaw(pm, pm.idxHeadYaw, head);
}

float ClampRaw(PoseModel pm, int i, float v)
{
	float lo = pm.start[i], hi = pm.end[i];
	if (lo > hi) { float x = lo; lo = hi; hi = x; }
	if (v < lo) return lo;
	if (v > hi) return hi;
	return v;
}

float RecPoseRaw(ArrayList h, int idx, PoseModel pm, int i)
{
	if (i == -1)
		return 0.0;
	return PoseRaw(pm, i, view_as<float>(h.Get(idx, REC_POSE + i)));
}

// The client's feet yaw, body_yaw and head_yaw minus the server's at the record in effect at t,
// from the reset this run of records starts at. False when there is no reset within
// SPAWN_TURN_TIME or the player did not move during the client's window (no difference).
bool ClientSpawnTurn(int entity, PoseModel pm, float t, float &dFeet, float &dBody, float &dHead,
	float &resetAgo, float &modelFeet, float &recFeet, bool &isNew, bool &jumped)
{
	isNew = false;
	jumped = false;
	dFeet = 0.0; dBody = 0.0; dHead = 0.0;
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] < 2 || g_iShooter <= 0 || g_iShooter > MaxClients)
		return false;
	int n;
	int idx = FindRecIndex(entity, t, n);
	if (idx == -1)
		return false;
	int size = g_iRingSize;
	float R;
	bool created;
	int r = ClientResetIndex(entity, t, SPAWN_TURN_TIME, R, created);
	isNew = created;
	if (r == -1 || r == idx || h.Get(r, REC_MODEL) != h.Get(idx, REC_MODEL))
		return false;

	// the client's speed estimate is 0 while it draws up to wEnd (see FindResetWindow)
	float wEnd = R + RESET_WINDOW_TIME;
	float lookRange = (GetClientTeam(entity) == 2) ? 90.0 : 45.0;

	float eye = view_as<float>(h.Get(r, REC_EYEY));
	float fs = (h.Get(r, REC_HASYAW) != 0) ? view_as<float>(h.Get(r, REC_RYAW)) : eye;
	float gs = fs, fc = fs, gc = fs;
	// a new entity's animstate starts its feet and goal at the eye yaw of the first state the client
	// got (anim_showstate: -10.0 on the client, the eye yaw one tick after the spawn, while the
	// server's feet started at the spawn's 0)
	if (created)
	{
		fc = AngleNorm(eye);
		gc = fc;
	}
	// the client's ground speed for its goal rule (the same on both sides)
	float ground = PlayerGroundSpeed(entity, t, pm);
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float bs = RecPoseRaw(h, r, pm, pm.idxBodyYaw), hs = RecPoseRaw(h, r, pm, pm.idxHeadYaw);
	float bc = bs, hc = hs;
	// a client that has just made the entity starts its pose parameters at 0 (normalized), the bottom
	// of their range; the server's start at 0 degrees. anim_showstate of a spawned Jockey: client
	// body_yaw -87.1 one frame in, easing toward the aim as below to within 0.2 degrees all the way
	// to the shot, while the server's started at 0.
	if (created)
	{
		if (pm.idxBodyYaw != -1) bc = pm.start[pm.idxBodyYaw];
		if (pm.idxHeadYaw != -1) hc = pm.start[pm.idxHeadYaw];
	}
	float t0 = R;
	bool wasWin = true;
	jumped = false;
	for (int j = r; j != idx; )
	{
		int jn = (j + 1) % size;
		j = jn;
		float t1 = view_as<float>(h.Get(jn, REC_SIM));
		float dt = t1 - t0;
		if (dt <= 0.0)
			continue;
		t0 = t1;
		if (h.Get(jn, REC_HASEYE))
			eye = view_as<float>(h.Get(jn, REC_EYEY));
		float vx = view_as<float>(h.Get(jn, REC_VEL)), vy = view_as<float>(h.Get(jn, REC_VEL + 1));
		float speed = SquareRoot(vx * vx + vy * vy);
		bool moving = speed > 0.5;
		float velYaw = moving ? RadToDeg(ArcTangent2(vy, vx)) : 0.0;
		bool fast = false;
		if (moving)
		{
			int seq = h.Get(jn, REC_SEQ);
			if (SeqKind(pm, seq) & SK_NOGS)
				fast = true;                         // ground speed 0
			else if (pm.idxMoveX != -1 && pm.idxMoveY != -1)
			{
				// the server's move blend is clamp(speed / ground speed): over 0.9 = past 90%
				float mx = RecPoseRaw(h, jn, pm, pm.idxMoveX), my = RecPoseRaw(h, jn, pm, pm.idxMoveY);
				fast = mx * mx + my * my > 0.81;
			}
		}
		float rt = moving ? FEET_TURN_MOVING : 1.0;

		// server
		gs = FeetGoal(gs, eye, fast, velYaw, lookRange);
		fs = FeetStep(fs, gs, eye, rt, dt);
		AimStep(bs, hs, eye, fs, moving, dt, pm);

		// shooter's client: its speed estimate, 0 in the window, else rebuilt from the snapshots it
		// got (ClientVelocityAt). When the window ends while the player moves, the client mostly
		// draws its newest snapshot, undelayed, for one frame, and its estimate jumps far past any
		// threshold (anim_showstate: 1150, 559 and 2615 u/s in three of four spawns), which points the
		// feet goal at the movement at once. The server cannot see which frame does it; the jump is
		// assumed.
		float cspeed = 0.0, cyaw = velYaw;
		if (t1 > wEnd)
		{
			float cv[3];
			if (ClientVelocityAt(entity, t1, lerp, cv))
			{
				cspeed = SquareRoot(cv[0] * cv[0] + cv[1] * cv[1]);
				if (cspeed > 0.5)
					cyaw = RadToDeg(ArcTangent2(cv[1], cv[0]));
			}
			else
				cspeed = speed;
		}
		bool cmoving = cspeed > 0.5;
		bool cfast = false;
		if (cmoving)
		{
			if (SeqKind(pm, h.Get(jn, REC_SEQ)) & SK_NOGS)
				cfast = true;
			else
				cfast = ground > 0.0 ? cspeed > 0.9 * ground : fast;
		}
		bool win = t1 <= wEnd;
		if (!win && wasWin && moving)
		{
			cfast = true;           // the jump: toward the movement (newest snapshot - drawn position)
			cmoving = true;
			cyaw = velYaw;
			jumped = true;
		}
		wasWin = win;
		gc = FeetGoal(gc, eye, cfast, cyaw, lookRange);
		fc = FeetStep(fc, gc, eye, cmoving ? FEET_TURN_MOVING : 1.0, dt);
		AimStep(bc, hc, eye, fc, cmoving, dt, pm);
	}
	dFeet = AngleDiff(fc, fs);
	dBody = bc - bs;
	dHead = hc - hs;
	resetAgo = t - R;
	modelFeet = fs;
	recFeet = (h.Get(idx, REC_HASYAW) != 0) ? view_as<float>(h.Get(idx, REC_RYAW)) : fs;
	return true;
}

// body_pitch and head_pitch as the shooter's client eased them up to t (ComputePoseParam_AimPitch,
// server_srv.so 0x5001f0, the same code in client.dll): each frame
//   body_pitch += 12 * dt * (eye pitch - body_pitch),  head_pitch += 12 * dt * (eye pitch - body_pitch - head_pitch)
// (no step past the target), from the networked eye pitch. The server runs the same with its own
// animstate's eye pitch, which is not always the networked one. Run over the records of the last
// AIM_PITCH_TIME (the start state is gone to e^-7 by then), or from the moment the client made the
// entity, where both start at the bottom of their range (anim_showstate: body_pitch -84.2 one frame
// after a Jockey spawned, then -68.4, -52.2, -30.4, -15.2 toward 15 at 12/s).
#define AIM_PITCH_TIME 0.6
#define AIM_PITCH_RATE 12.0

bool ClientAimPitch(int entity, PoseModel pm, float t, float eyeAtT, float &body, float &head, float &from, bool &created)
{
	created = false;
	from = -1.0;
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] < 2)
		return false;
	int n;
	int idx = FindRecIndex(entity, t, n);
	if (idx == -1)
		return false;
	int size = g_iRingSize, count = g_iCount[entity];
	int model = h.Get(idx, REC_MODEL);
	float rs;
	int r = ClientResetIndex(entity, t, AIM_PITCH_TIME, rs, created);
	if (!created)
		r = -1;
	// oldest record to start from
	int st = idx;
	for (int k = n, j = idx; k < count; k++, j = (j - 1 + size) % size)
	{
		if (h.Get(j, REC_MODEL) != model || t - view_as<float>(h.Get(j, REC_SIM)) > AIM_PITCH_TIME)
			break;
		if (!h.Get(j, REC_HASEYE))
			break;
		st = j;
		if (j == r)
			break;
	}
	created = (st == r);
	int iB = pm.idxBodyPitch, iH = pm.idxHeadPitch;
	bool haveH = iH != -1 && pm.end[iH] != pm.start[iH];
	float eye = AngleNorm(view_as<float>(h.Get(st, REC_EYEP)));
	if (created)
	{
		body = pm.start[iB];
		head = haveH ? pm.start[iH] : 0.0;
	}
	else
	{
		body = ClampRaw(pm, iB, eye);
		head = 0.0;
	}
	float t0 = view_as<float>(h.Get(st, REC_SIM));
	from = t - t0;
	for (int j = st; ; )
	{
		float t1, e1;
		bool last = (j == idx);
		if (last)
		{
			t1 = t;
			e1 = eyeAtT;
		}
		else
		{
			j = (j + 1) % size;
			t1 = view_as<float>(h.Get(j, REC_SIM));
			e1 = h.Get(j, REC_HASEYE) ? AngleNorm(view_as<float>(h.Get(j, REC_EYEP))) : eye;
		}
		float dt = t1 - t0;
		if (dt > 0.0)
		{
			eye = e1;
			float g = eye - body, s1 = AIM_PITCH_RATE * dt * g;
			if (FloatAbs(g) < FloatAbs(s1)) s1 = g;
			float nb = body + s1;
			float g2 = eye - nb - head, s2 = AIM_PITCH_RATE * dt * g2;
			if (FloatAbs(g2) < FloatAbs(s2)) s2 = g2;
			body = ClampRaw(pm, iB, nb);
			head = haveH ? ClampRaw(pm, iH, head + s2) : 0.0;
			t0 = t1;
		}
		if (last)
			break;
	}
	return true;
}

// Adds the client's spawn-window turn difference to the feet (render) yaw and to body_yaw /
// head_yaw, before the move blend is worked out from that feet yaw.
void ApplyClientSpawnTurn(int entity, float t, float poses[MAXPOSE], float &yaw)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return;
	float dF, dB, dH, ago, mf, rf;
	bool isNew, jumped;
	if (!ClientSpawnTurn(entity, pm, t, dF, dB, dH, ago, mf, rf, isNew, jumped))
		return;
	if (FloatAbs(dF) < 0.05 && FloatAbs(dB) < 0.05 && FloatAbs(dH) < 0.05)
		return;
	float before = yaw;
	yaw = AngleNorm(yaw + dF);
	float b0 = 0.0, b1 = 0.0;
	if (pm.idxBodyYaw != -1 && pm.end[pm.idxBodyYaw] != pm.start[pm.idxBodyYaw])
	{
		b0 = PoseRaw(pm, pm.idxBodyYaw, poses[pm.idxBodyYaw]);
		poses[pm.idxBodyYaw] = PoseValueFromDegrees(pm, pm.idxBodyYaw, b0 + dB);
		b1 = PoseRaw(pm, pm.idxBodyYaw, poses[pm.idxBodyYaw]);
	}
	if (pm.idxHeadYaw != -1 && pm.end[pm.idxHeadYaw] != pm.start[pm.idxHeadYaw])
		poses[pm.idxHeadYaw] = PoseValueFromDegrees(pm, pm.idxHeadYaw, PoseRaw(pm, pm.idxHeadYaw, poses[pm.idxHeadYaw]) + dH);
	g_iStatSpawnTurn++;
	if (g_iDebug > 0)
		Dbg(entity, "[posesync] ent %d: %.2f s after a spawn / interpolation reset: your client's turn (0 speed estimate in its window%s%s), feet yaw %.1f -> %.1f (%s%.1f deg), body_yaw %.1f -> %.1f, head_yaw %s%.1f (model of the server's feet %.1f, recorded %.1f)",
			entity, ago, jumped ? ", then the one-frame jump in its estimate as it ended: feet goal to the movement" : "",
			isNew ? "; new entity: body_yaw from the bottom of its range" : "", before, yaw, dF >= 0.0 ? "+" : "", dF, b0, b1, dH >= 0.0 ? "+" : "", dH, mf, rf);
}

// Sequences during which the client's animstate holds its eye angles.
bool IsEyeLockAct(PoseModel pm, int seq)
{
	return (SeqKind(pm, seq) & SK_EYELOCK) != 0;
}

// Activities for which the client's CTerrorPlayerAnimState::GetCurrentMaxGroundSpeed (0x1027e270) is 0:
// it maps the main activity through 0x1027de60 and only the idle, walk, run, crouch walk and jump
// families get a speed. With 0 the move blend (0x10281e50) writes move_x = move_y = 0, whatever the
// speed estimate. Taken from client.dll by running 0x1027de60 over every registered activity.
bool ActZeroGroundSpeed(const char[] act)
{
	static const char acts[][] = {
		"ACT_DIESIMPLE",
		"ACT_CLIMB_UP",
		"ACT_CLIMB_DOWN",
		"ACT_CROUCHIDLE",
		"ACT_IDLE_INCAP",
		"ACT_TERROR_HIT_BY_TANKPUNCH",
		"ACT_TERROR_IDLE_FALL_FROM_TANKPUNCH",
		"ACT_TERROR_TANKPUNCH_LAND",
		"ACT_TERROR_HIT_BY_CHARGER",
		"ACT_TERROR_IDLE_FALL_FROM_CHARGERHIT",
		"ACT_TERROR_CHARGERHIT_LAND_SLOW",
		"ACT_TERROR_CROUCH_HEAL_SELF",
		"ACT_TERROR_CROUCH_HEAL_FRIEND",
		"ACT_TERROR_CROUCH_HEAL_INCAPACITATED",
		"ACT_TERROR_CROUCH_HEAL_INCAPACITATED_ABOVE",
		"ACT_TERROR_SHOVED_FORWARD",
		"ACT_TERROR_SHOVED_BACKWARD",
		"ACT_TERROR_SHOVED_LEFTWARD",
		"ACT_TERROR_SHOVED_RIGHTWARD",
		"ACT_TERROR_DIE_FROM_STAND",
		"ACT_TERROR_DIE_WHILE_RUNNING",
		"ACT_TERROR_INCAP_TO_STAND",
		"ACT_TERROR_INCAP_TO_CROUCH",
		"ACT_IDLE_INCAP_PISTOL",
		"ACT_IDLE_INCAP_ELITES",
		"ACT_FALL",
		"ACT_TERROR_CLIMB_36_FROM_STAND",
		"ACT_TERROR_CLIMB_38_FROM_STAND",
		"ACT_TERROR_CLIMB_50_FROM_STAND",
		"ACT_TERROR_CLIMB_70_FROM_STAND",
		"ACT_TERROR_CLIMB_115_FROM_STAND",
		"ACT_TERROR_CLIMB_130_FROM_STAND",
		"ACT_TERROR_CLIMB_150_FROM_STAND",
		"ACT_TERROR_CLIMB_166_FROM_STAND",
		"ACT_TERROR_HUNTER_LUNGE",
		"ACT_TERROR_HUNTER_POUNCE",
		"ACT_TERROR_SMOKER_PREPARE_TONGUE_LAUNCH",
		"ACT_TERROR_SMOKER_SENDING_OUT_TONGUE",
		"ACT_TERROR_SMOKER_SENDING_OUT_TONGUE_IDLE",
		"ACT_TERROR_SMOKER_REELING_IN_TONGUE",
		"ACT_TERROR_SMOKER_REELING_IN_TONGUE_IDLE",
		"ACT_TERROR_SMOKER_CRITICAL_ATTACK",
		"ACT_TERROR_SMOKER_CRITICAL_ATTACK_IDLE",
		"ACT_HULK_THROW",
		"ACT_TANK_OVERHEAD_THROW",
		"ACT_TERROR_HUNTER_POUNCE_MELEE",
		"ACT_TERROR_HUNTER_POUNCE_KNOCKOFF_L",
		"ACT_TERROR_HUNTER_POUNCE_KNOCKOFF_R",
		"ACT_TERROR_HUNTER_POUNCE_KNOCKOFF_BACKWARD",
		"ACT_TERROR_HUNTER_POUNCE_KNOCKOFF_FORWARD",
		"ACT_IDLE_POUNCED",
		"ACT_TERROR_POUNCED_TO_STAND",
		"ACT_TERROR_TANKROCK_TO_STAND",
		"ACT_TERROR_RAGE_AT_ENEMY",
		"ACT_TERROR_RAGE_AT_KNOCKDOWN",
		"ACT_CROUCHIDLE_RIFLE",
		"ACT_CROUCHIDLE_SHOTGUN",
		"ACT_CROUCHIDLE_PUMPSHOTGUN",
		"ACT_CROUCHIDLE_GREN",
		"ACT_CROUCHIDLE_GREN_PULL_BACK",
		"ACT_CROUCHIDLE_SNIPER",
		"ACT_CROUCHIDLE_SNIPER_ZOOMED",
		"ACT_CROUCHIDLE_SMG",
		"ACT_CROUCHIDLE_FIRSTAIDKIT",
		"ACT_CROUCHIDLE_PISTOL",
		"ACT_CROUCHIDLE_ELITES"
	};
	for (int i = 0; i < sizeof(acts); i++)
		if (StrEqual(act, acts[i], false))
			return true;
	return false;
}

// Activities during which the client's animstate holds its eye angles.
bool ActIsEyeLock(const char[] act)
{
	if (StrContains(act, "ACT_TERROR_SHOVED_", false) == 0)
	{
		// ACT_TERROR_SHOVED_{FORWARD,BACKWARD,LEFTWARD,RIGHTWARD}[_CHAINSAW|_BAT|_MELEE], not _INTO_WALL / _FROM_SIT
		return StrContains(act, "_INTO_WALL", false) == -1 && StrContains(act, "_FROM_SIT", false) == -1;
	}
	if (StrContains(act, "ACT_TERROR_HUNTER_POUNCE_KNOCKOFF_", false) == 0)
		return true;
	if (StrContains(act, "ACT_TERROR_CHARGER_POUND", false) == 0)      // POUND_* and POUNDED_*
		return true;
	return StrEqual(act, "ACT_TERROR_CHARGER_PUMMEL", false) || StrEqual(act, "ACT_TERROR_CHARGER_PUMMELED", false)
		|| StrEqual(act, "ACT_TERROR_SLAMMED_WALL", false) || StrEqual(act, "ACT_TERROR_SLAMMED_GROUND", false);
}

// If the record in effect at 'clock' is in an eye-lock activity: start = the first record of that run.
bool FindEyeLockStart(int entity, PoseModel pm, float clock, float &start)
{
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] == 0)
		return false;
	int size = g_iRingSize, count = g_iCount[entity];
	int n;
	g_bLockFromSnap = false;
	int idx = FindRecIndex(entity, clock, n);
	if (idx == -1 || !IsEyeLockAct(pm, h.Get(idx, REC_SEQ)))
		return false;
	start = view_as<float>(h.Get(idx, REC_SIM));
	int model = h.Get(idx, REC_MODEL);
	for (n++, idx = (idx - 1 + size) % size; n < count; n++, idx = (idx - 1 + size) % size)
	{
		if (h.Get(idx, REC_MODEL) != model || !IsEyeLockAct(pm, h.Get(idx, REC_SEQ)))
			return true;
		start = view_as<float>(h.Get(idx, REC_SIM));
	}
	// the lock started before the oldest record (a long stagger at a low tick rate, a pummel): the
	// snapshot taken when it started has its eye values
	if (entity < PTX_MAX && g_iLockSnapN[entity] > 0 && g_iLockSnapModel[entity] == model
		&& g_fLockSnapStart[entity] <= start + 0.0001 && start - g_fLockSnapStart[entity] < 60.0)
	{
		start = g_fLockSnapStart[entity];
		g_bLockFromSnap = true;
		return true;
	}
	return false;
}

// Networked eye angles at time t, interpolated between records like the client does.
bool LookupEye(int entity, float t, float &pitch, float &yaw)
{
	// the client interpolates m_angEyeAngles (linearly, it is a QAngle) between the states it received
	if (entity <= MaxClients && entity < PTX_MAX && g_iShooter > 0 && g_iShooter < PTX_MAX && g_iPlTxCount[g_iShooter][entity] > 0)
	{
		CSamples cs;
		float cvarLerp;
		// the client draws TICKS_TO_TIME(TIME_TO_TICKS(lerp) + 1) behind its clock
		float clock = t + float(RoundToNearest(GetShooterLerp(g_iShooter, cvarLerp) / g_fTick) + 1) * g_fTick;
		if (BuildClientSamples(entity, g_iShooter, clock, t, cs))
		{
			ArrayList h = g_hHistory[entity];
			int ia = (cs.nBelow > 0) ? cs.iB[0] : cs.iN;
			if (h.Get(ia, REC_HASEYE))
			{
				pitch = AngleNorm(view_as<float>(h.Get(ia, REC_EYEP)));
				yaw = AngleNorm(view_as<float>(h.Get(ia, REC_EYEY)));
				if (cs.nBelow > 0 && cs.haveNewer && h.Get(cs.iN, REC_HASEYE) && cs.tN > cs.tB[0])
				{
					float f = (t - cs.tB[0]) / (cs.tN - cs.tB[0]);
					if (f > 2.0) f = 2.0;
					pitch += AngleDiff(AngleNorm(view_as<float>(h.Get(cs.iN, REC_EYEP))), pitch) * f;
					yaw = AngleNorm(yaw + AngleDiff(AngleNorm(view_as<float>(h.Get(cs.iN, REC_EYEY))), yaw) * f);
				}
				return true;
			}
		}
	}
	int a[REC_SIZE], b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, t, a, b, haveB, frac) || !a[REC_HASEYE])
		return false;
	pitch = AngleNorm(view_as<float>(a[REC_EYEP]));
	yaw = AngleNorm(view_as<float>(a[REC_EYEY]));
	if (haveB && b[REC_HASEYE] && frac > 0.0)
	{
		pitch += AngleDiff(AngleNorm(view_as<float>(b[REC_EYEP])), pitch) * frac;
		yaw = AngleNorm(yaw + AngleDiff(AngleNorm(view_as<float>(b[REC_EYEY])), yaw) * frac);
	}
	return true;
}

// Players: sets the eye-driven pose parameters (body_pitch, body_yaw, head_pitch, head_yaw) and the
// render yaw to what the client drew with, at posTarget (the time the client draws) or, during an
// eye lock, at the time the client drew when the lock started.
void ApplyEyeDriven(int entity, float target, float posTarget, float poses[MAXPOSE], float &yaw, bool haveYaw)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return;
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float drawT = posTarget;
	float eyeT = drawT;

	// eye lock: the client froze its eye angles when the stagger (or pummel, ...) started
	bool locked = false;
	float lockStart = 0.0, clock = 0.0;
	if (lerp > 0.0)
	{
		clock = ClientClock(entity, target, lerp);
		if (FindEyeLockStart(entity, pm, clock, lockStart))
		{
			// the client drew the eyes this far behind its clock (not the clamped clock above)
			float delay = target + lerp + float(CLIENT_CLOCK_TICKS) * g_fTick - drawT;
			float lockT = lockStart - delay;
			if (lockT < eyeT)
			{
				eyeT = lockT;
				locked = true;
			}
		}
	}

	int iBodyPitch = pm.idxBodyPitch, iHeadPitch = pm.idxHeadPitch, iBodyYaw = pm.idxBodyYaw;

	float serverPitch = 0.0, eyePitch, eyeYaw;
	bool pitchSet = false, haveEye = false;
	float feet0 = 0.0, feetNow = 0.0;
	bool lockYaw = false;

	if (locked)
	{
		// The client holds the eye angles it had when the lock started; its goal feet yaw is that eye
		// yaw, and the feet keep turning toward it (seen with anim_showstate: feet from -166.9 to the
		// held -129.0 within half a second of a shove, body_yaw following). The server's eyes and
		// feet go on following the real aim.
		float ep[MAXPOSE];
		float rs, ps, fr, eyaw;
		bool ehave;
		bool inHistory = !g_bLockFromSnap && LookupPoses(entity, eyeT, ep, rs, ps, fr, eyaw, ehave) && rs <= eyeT + 0.0001
			&& LookupEye(entity, eyeT, eyePitch, eyeYaw);
		if (inHistory)
		{
			haveEye = true;
			if (pm.idxHeadPitch != -1) poses[pm.idxHeadPitch] = ep[pm.idxHeadPitch];
			if (pm.idxHeadYaw != -1)   poses[pm.idxHeadYaw] = ep[pm.idxHeadYaw];
			if (ehave)
			{
				feet0 = eyaw;
				lockYaw = true;
			}
		}
		else if (LockSnapAt(entity, eyeT, eyePitch, eyeYaw, feet0))
		{
			haveEye = true;
			lockYaw = true;
		}
		if (lockYaw)
		{
			g_bEyeLocked = true;
			feetNow = ConvergeFeet(feet0, eyeYaw, clock - lockStart);
			if (iBodyYaw != -1 && pm.end[iBodyYaw] != pm.start[iBodyYaw])
				SetPoseLocal(pm, poses, iBodyYaw, AngleDiff(eyeYaw, feetNow));
			if (haveYaw)
			{
				if (g_iDebug > 0)
					Dbg(entity, "[posesync] ent %d: eye angles held since the client started the stagger: eye yaw %.1f, feet yaw %.1f then -> %.1f after %.2f s of turning toward it (server's %.1f)",
						entity, eyeYaw, feet0, feetNow, clock - lockStart, yaw);
				yaw = feetNow;
			}
		}
	}
	else if (FloatAbs(eyeT - target) > 0.0001)
	{
		// body_yaw, head_pitch, head_yaw and the feet yaw from the time the client draws (body_pitch
		// is rebuilt from the eye pitch below)
		float ep[MAXPOSE];
		float rs, ps, fr, eyaw;
		bool ehave;
		if (LookupPoses(entity, eyeT, ep, rs, ps, fr, eyaw, ehave))
		{
			if (pm.idxBodyYaw != -1)   poses[pm.idxBodyYaw] = ep[pm.idxBodyYaw];
			if (pm.idxHeadPitch != -1) poses[pm.idxHeadPitch] = ep[pm.idxHeadPitch];
			if (pm.idxHeadYaw != -1)   poses[pm.idxHeadYaw] = ep[pm.idxHeadYaw];
			if (haveYaw && ehave)
			{
				if (g_iDebug > 0)
					Dbg(entity, "[posesync] ent %d: eye-driven values from %.3f (the time the client draws): body yaw %.1f -> %.1f",
						entity, eyeT, yaw, eyaw);
				yaw = eyaw;
			}
		}
	}

	if (!haveEye && !locked)
		haveEye = LookupEye(entity, eyeT, eyePitch, eyeYaw);
	float easedFrom = -1.0;
	bool pitchCreated = false;
	if (iBodyPitch != -1 && pm.end[iBodyPitch] != pm.start[iBodyPitch] && haveEye)
	{
		float range = pm.end[iBodyPitch] - pm.start[iBodyPitch];
		serverPitch = pm.start[iBodyPitch] + poses[iBodyPitch] * range;
		// the client eases body_pitch toward the eye pitch (see ClientAimPitch); during an eye lock it
		// eases toward the held pitch, which has long been reached
		float bp = eyePitch, hp = 0.0;
		if (!locked)
			ClientAimPitch(entity, pm, eyeT, eyePitch, bp, hp, easedFrom, pitchCreated);
		poses[iBodyPitch] = PoseValueFromDegrees(pm, iBodyPitch, bp);
		pitchSet = true;
		if (iHeadPitch != -1 && pm.end[iHeadPitch] != pm.start[iHeadPitch])
			poses[iHeadPitch] = PoseValueFromDegrees(pm, iHeadPitch, hp);
	}

	if (g_iDebug > 0)
	{
		if (locked)
		{
			char label[SEQ_NAME_LEN + 64];
			int a[REC_SIZE], b[REC_SIZE];
			bool hb;
			float fr;
			if (FindRecordPair(entity, clock, a, b, hb, fr))
				SeqLabel(pm, a[REC_SEQ], label, sizeof(label));
			else
				strcopy(label, sizeof(label), "?");
			Dbg(entity, "[posesync] ent %d eye lock: the client plays %s since %.3f and stopped taking new eye angles then; eye values from %.3f (= %.3f - client clock %.3f + draw time %.3f)",
				entity, label, lockStart, eyeT, lockStart, clock, drawT);
		}
		if (pitchSet)
		{
			if (easedFrom >= 0.0)
				Dbg(entity, "[posesync] ent %d body_pitch: %.1f (networked eye pitch %.1f at %.3f, eased toward it at 12/s since %.2f s before%s) instead of the server's %.1f",
					entity, pm.start[iBodyPitch] + poses[iBodyPitch] * (pm.end[iBodyPitch] - pm.start[iBodyPitch]), eyePitch, eyeT, easedFrom,
					pitchCreated ? ", from the bottom of its range when your client made the entity" : "", serverPitch);
			else
				Dbg(entity, "[posesync] ent %d body_pitch: %.1f (networked eye pitch at %.3f) instead of the server's %.1f",
					entity, pm.start[iBodyPitch] + poses[iBodyPitch] * (pm.end[iBodyPitch] - pm.start[iBodyPitch]), eyeT, serverPitch);
		}
	}
}

// ---------------------------------------------------------------------------
// Hitbox drawer (sm_posesync_drawhitboxes): the server's lag compensated hitboxes, as the bullets
// saw them, drawn as beams for the shooter. sv_showimpacts only works on a listen server; this
// works on a dedicated one too. The boxes are taken from the bone cache before anything is put back.
// ---------------------------------------------------------------------------

// Hitbox corners in world space: bone matrix columns are forward (x), left (y), up (z);
// AngleVectors of the bone angles gives forward, right = -left, up.
void BoxCorner(const float o[3], const float f[3], const float r[3], const float u[3], float x, float y, float z, float out[3])
{
	for (int a = 0; a < 3; a++)
		out[a] = o[a] + f[a] * x - r[a] * y + u[a] * z;
}

// Ray against one oriented box. Returns the entry distance along the ray, or -1.0.
float RayBox(const float eye[3], const float dir[3], float len, const float o[3], const float f[3], const float r[3], const float u[3], const float mins[3], const float maxs[3])
{
	float d[3];
	SubtractVectors(eye, o, d);
	float lo[3], ld[3];
	lo[0] = GetVectorDotProduct(d, f);   ld[0] = GetVectorDotProduct(dir, f);
	lo[1] = -GetVectorDotProduct(d, r);  ld[1] = -GetVectorDotProduct(dir, r);
	lo[2] = GetVectorDotProduct(d, u);   ld[2] = GetVectorDotProduct(dir, u);
	float tmin = 0.0, tmax = len;
	for (int a = 0; a < 3; a++)
	{
		if (FloatAbs(ld[a]) < 0.000001)
		{
			if (lo[a] < mins[a] || lo[a] > maxs[a])
				return -1.0;
			continue;
		}
		float t1 = (mins[a] - lo[a]) / ld[a];
		float t2 = (maxs[a] - lo[a]) / ld[a];
		if (t1 > t2) { float t = t1; t1 = t2; t2 = t; }
		if (t1 > tmin) tmin = t1;
		if (t2 < tmax) tmax = t2;
		if (tmin > tmax)
			return -1.0;
	}
	return tmin;
}

// Bone frames of every hitbox of the entity, from the server's bone cache.
int GetHitboxFrames(int entity, ArrayList boxes, float org[MAX_DRAW_BOXES][3], float fwd[MAX_DRAW_BOXES][3], float rgt[MAX_DRAW_BOXES][3], float up[MAX_DRAW_BOXES][3])
{
	int n = boxes.Length;
	if (n > MAX_DRAW_BOXES)
		n = MAX_DRAW_BOXES;
	for (int i = 0; i < n; i++)
	{
		int bone = boxes.Get(i, HB_BONE);
		float ang[3];
		SDKCall(g_hGetBoneOrigin, entity, org[i], bone);
		SDKCall(g_hGetBoneAngles, entity, ang, bone);
		GetAngleVectors(ang, fwd[i], rgt[i], up[i]);
	}
	return n;
}

// Queues the hitboxes of the entity the shooter aimed at, at most every DRAW_INTERVAL seconds.
void DrawShotHitboxes(int shooter)
{
	if (g_hGetBoneOrigin == null || g_hGetBoneAngles == null || g_iLaser == -1)
		return;
	if (shooter <= 0 || shooter > MaxClients || !IsClientInGame(shooter) || IsFakeClient(shooter))
		return;
	float nowReal = GetEngineTime();
	if (nowReal < g_fNextDraw[shooter] || g_hBeams.Length - g_iBeamRead > MAX_QUEUED_BEAMS)
		return;

	float org[MAX_DRAW_BOXES][3], fwd[MAX_DRAW_BOXES][3], rgt[MAX_DRAW_BOXES][3], up[MAX_DRAW_BOXES][3];
	int bestEnt = -1, bestBox = -1;
	float bestT, bestMiss;
	bool bestHit;
	FindAimTarget(shooter, bestEnt, bestBox, bestT, bestMiss, bestHit);

	if (bestEnt == -1)
		return;
	g_fNextDraw[shooter] = nowReal + DRAW_INTERVAL;

	PoseModel pm;
	GetPoseModel(bestEnt, pm);
	int n = GetHitboxFrames(bestEnt, pm.hitboxes, org, fwd, rgt, up);
	int userid = GetClientUserId(shooter);
	int green = PackColor(0, 255, 0), yellow = PackColor(255, 255, 0), white = PackColor(255, 255, 255);
	for (int b = 0; b < n; b++)
	{
		float mins[3], maxs[3];
		for (int a = 0; a < 3; a++)
		{
			mins[a] = pm.hitboxes.Get(b, HB_MINS + a);
			maxs[a] = pm.hitboxes.Get(b, HB_MAXS + a);
		}
		int color = !bestHit ? white : (b == bestBox ? yellow : green);
		QueueBox(org[b], fwd[b], rgt[b], up[b], mins, maxs, color, userid);
	}

	char cls[64];
	GetEntityClassname(bestEnt, cls, sizeof(cls));
	char msg[256];
	if (bestHit)
		FormatEx(msg, sizeof(msg), "[posesync] server hitboxes of ent %d (%s) drawn: your aim ray hits hitbox %d (group %d) %.0f units away",
			bestEnt, cls, bestBox, pm.hitboxes.Get(bestBox, HB_GROUP), bestT);
	else
		FormatEx(msg, sizeof(msg), "[posesync] server hitboxes of ent %d (%s) drawn in white: your aim ray misses them all, closest is hitbox %d (group %d) by %.1f units",
			bestEnt, cls, bestBox, pm.hitboxes.Get(bestBox, HB_GROUP), bestMiss);
	Format(msg, sizeof(msg), "%s; engine latency allowance %.0f ms", msg, g_fPingAllow[shooter] * 1000.0);
	PrintToConsole(shooter, "%s", msg);
	if (g_iDebug > 0)
		PrintToServer("%s", msg);

	// send the first batch right away, the rest over the next ticks
	SendQueuedBeams(DRAW_BEAMS_PER_TICK);
	g_iBeamTick = GetGameTickCount();
}

// The rewound entity whose server hitboxes the shooter's aim ray goes through (nearest), else the
// one it passes closest to (within 48 units of a box centre); -1 if none.
void FindAimTarget(int shooter, int &bestEnt, int &bestBox, float &bestT, float &bestMiss, bool &bestHit)
{
	bestEnt = -1;
	bestBox = -1;
	bestHit = false;
	if (g_hGetBoneOrigin == null || g_hGetBoneAngles == null)
		return;   // the bone signatures are optional
	float eye[3], eyeAng[3], dir[3];
	GetClientEyePosition(shooter, eye);
	GetClientEyeAngles(shooter, eyeAng);
	GetAngleVectors(eyeAng, dir, NULL_VECTOR, NULL_VECTOR);
	float len = 4096.0;

	float org[MAX_DRAW_BOXES][3], fwd[MAX_DRAW_BOXES][3], rgt[MAX_DRAW_BOXES][3], up[MAX_DRAW_BOXES][3];
	bestEnt = -1;
	bestBox = -1;
	bestT = len + 1.0;
	bestMiss = 48.0;
	bestHit = false;

	for (int i = 0; i < g_iAppliedCount; i++)
	{
		int entity = g_iAppliedList[i];
		if (entity == shooter || EntRefToEntIndex(g_iAppliedRef[entity]) != entity)
			continue;
		PoseModel pm;
		if (!GetPoseModel(entity, pm) || pm.hitboxes == null || pm.hitboxes.Length == 0)
			continue;
		int n = GetHitboxFrames(entity, pm.hitboxes, org, fwd, rgt, up);
		for (int b = 0; b < n; b++)
		{
			float mins[3], maxs[3];
			for (int a = 0; a < 3; a++)
			{
				mins[a] = pm.hitboxes.Get(b, HB_MINS + a);
				maxs[a] = pm.hitboxes.Get(b, HB_MAXS + a);
			}
			float t = RayBox(eye, dir, len, org[b], fwd[b], rgt[b], up[b], mins, maxs);
			if (t >= 0.0)
			{
				if (!bestHit || t < bestT)
				{
					bestHit = true; bestT = t; bestEnt = entity; bestBox = b;
				}
				continue;
			}
			if (bestHit)
				continue;
			// closest approach of the aim ray to the box centre
			float c[3], v[3];
			BoxCorner(org[b], fwd[b], rgt[b], up[b], (mins[0] + maxs[0]) * 0.5, (mins[1] + maxs[1]) * 0.5, (mins[2] + maxs[2]) * 0.5, c);
			SubtractVectors(c, eye, v);
			float along = GetVectorDotProduct(v, dir);
			if (along <= 0.0)
				continue;
			float miss = SquareRoot(GetVectorDotProduct(v, v) - along * along);
			if (miss < bestMiss)
			{
				bestMiss = miss; bestEnt = entity; bestBox = b;
			}
		}
	}

}

// RGBA packed into one cell for the beam queue.
int PackColor(int r, int g, int b)
{
	return (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16) | (0xFF << 24);
}

// Queues the 12 edges of one oriented box as beams for one client.
void QueueBox(const float o[3], const float f[3], const float r[3], const float u[3], const float mins[3], const float maxs[3], int color, int userid)
{
	float c[8][3];
	for (int k = 0; k < 8; k++)
		BoxCorner(o, f, r, u, (k & 1) ? maxs[0] : mins[0], (k & 2) ? maxs[1] : mins[1], (k & 4) ? maxs[2] : mins[2], c[k]);
	// 12 edges: corners that differ in exactly one bit
	for (int k = 0; k < 8; k++)
	{
		for (int bit = 1; bit < 8; bit <<= 1)
		{
			if (k & bit)
				continue;
			any e[BEAM_SIZE];
			for (int a = 0; a < 3; a++)
			{
				e[a] = c[k][a];
				e[3 + a] = c[k | bit][a];
			}
			e[6] = color;
			e[7] = userid;
			g_hBeams.PushArray(e);
		}
	}
}

// Sends up to 'budget' queued beams (too many temp entities in one tick get dropped).
void SendQueuedBeams(int budget)
{
	float life = DRAW_LIFE;
	int sent = 0;
	while (sent < budget && g_iBeamRead < g_hBeams.Length)
	{
		any e[BEAM_SIZE];
		g_hBeams.GetArray(g_iBeamRead++, e);
		int client = GetClientOfUserId(e[7]);
		if (client <= 0 || !IsClientInGame(client))
			continue;
		float a[3], b[3];
		for (int k = 0; k < 3; k++)
		{
			a[k] = e[k];
			b[k] = e[3 + k];
		}
		int packed = e[6];
		int color[4];
		color[0] = packed & 0xFF;
		color[1] = (packed >> 8) & 0xFF;
		color[2] = (packed >> 16) & 0xFF;
		color[3] = 255;
		TE_SetupBeamPoints(a, b, g_iLaser, 0, 0, 0, life, 0.4, 0.4, 1, 0.0, color, 0);
		TE_SendToClient(client);
		sent++;
	}
	if (g_iBeamRead >= g_hBeams.Length)
	{
		g_hBeams.Clear();
		g_iBeamRead = 0;
	}
}

// ---------------------------------------------------------------------------
// Animation frame on the client clock
//
// The client animates other players itself (DT_TerrorPlayer sends no sequence, cycle, layers or
// pose parameters). Its animstate runs on the client clock with the newest data it has, so the
// frame it shows (main sequence + cycle, overlay layers) is the server's at about target + lerp,
// while the position is drawn at the target time. The engine rewinds the cycle to the target time,
// a whole interpolation behind (for gunshots only with the StartLagCompensation detour; without it
// the cycle stays at the present). Common infected and witches send no cycle either:
// the client plays them from m_sequenceStartTime on its own clock.
// ---------------------------------------------------------------------------

// Newest record at or before t and the next newer one. Returns false without history.
bool FindRecordPair(int entity, float t, int a[REC_SIZE], int b[REC_SIZE], bool &haveB, float &frac)
{
	int n;
	int idx = FindRecIndex(entity, t, n);
	if (idx == -1)
		return false;
	ArrayList h = g_hHistory[entity];
	h.GetArray(idx, a);
	haveB = (n > 0);
	frac = 0.0;
	if (haveB)
	{
		h.GetArray((idx + 1) % g_iRingSize, b);
		float sa = view_as<float>(a[REC_SIM]), sb = view_as<float>(b[REC_SIM]);
		if (sb > sa)
			frac = (t - sa) / (sb - sa);
		if (frac < 0.0) frac = 0.0;
		if (frac > 1.0) frac = 1.0;
	}
	return true;
}

// Ring index of the newest record at or before t, -1 if there is none. n = how many records newer
// than it there are (the next newer one is at index + 1). Only the time cell of each record is
// read on the way, not whole records.
int FindRecIndex(int entity, float t, int &n)
{
	n = 0;
	ArrayList h = g_hHistory[entity];
	if (h == null)
		return -1;
	int size = g_iRingSize, count = g_iCount[entity];
	int idx = g_iHead[entity];
	for (; n < count; n++)
	{
		if (view_as<float>(h.Get(idx, REC_SIM)) <= t + 0.0001)
			return idx;
		idx = (idx - 1 + size) % size;
	}
	return -1;
}

// The shooter's client clock: target + lerp (the tick_count of the shooter's command).
// Players: never past the newest record (e.g. inside the reset window, where the target time
// already is the newest record the client has), plus CLIENT_CLOCK_TICKS (the client's clock is
// one tick ahead of its command's tick_count; past the newest record ComputeClockFrame advances the
// cycle at the sequence's rate).
float ClientClock(int entity, float target, float lerp)
{
	float clock = target + lerp;
	// common infected / witches: the client's frame comes from the start time on its own clock,
	// not from samples, so a common whose simulation time stopped (standing still) still plays on
	if (entity > MaxClients)
		return clock;
	if (g_hHistory[entity] != null && g_iCount[entity] > 0 && clock > g_fHeadSim[entity])
		clock = g_fHeadSim[entity];
	return clock + float(CLIENT_CLOCK_TICKS) * g_fTick;
}

// STUDIO_LOOPING (unknown sequences count as looping).
bool SeqLoops(PoseModel pm, int seq)
{
	if (pm.seqInfo == null || seq < 0 || seq >= pm.seqInfo.Length)
		return true;
	float info[SI_SIZE];
	pm.seqInfo.GetArray(seq, info);
	return (RoundToFloor(info[SI_FLAGS]) & 0x1) != 0;
}

// Interpolates a cycle between two records, across the wrap for looping sequences.
float LerpCycle(float c0, float c1, float frac, bool loops)
{
	if (loops && c1 < c0)
		c1 += 1.0;              // wrapped between the two records
	float c = c0 + (c1 - c0) * frac;
	if (loops)
		c -= float(RoundToFloor(c));
	else if (c > 1.0)
		c = 1.0;
	return c;
}

// Animation frame at the given clock: the record pair around it (cycle interpolated, or advanced at
// the sequence's rate past the newest record); for common infected / witches the cycle the client
// computes from m_sequenceStartTime. serverCycle is the server's own cycle at that clock, rate the
// cycles per second used, fromStart true when the cycle came from the start time (a[REC_SEQSTART]).
bool ComputeClockFrame(int entity, PoseModel pm, float clock, int &seq, float &cycle, float &serverCycle, float &rate, bool &fromStart, int a[REC_SIZE])
{
	int b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, clock, a, b, haveB, frac))
		return false;

	seq = a[REC_SEQ];
	cycle = view_as<float>(a[REC_CYCLE]);
	bool loops = SeqLoops(pm, seq);
	rate = SequenceRate(entity, pm, a, b, haveB);
	if (haveB && b[REC_SEQ] == seq && b[REC_PARITY] == a[REC_PARITY])
		cycle = LerpCycle(cycle, view_as<float>(b[REC_CYCLE]), frac, loops);
	else if (rate > 0.0)
	{
		// clock past the newest record of this sequence: advance it at the rate it was playing at
		// (measured from the records; a 3x3 move blend does not play at its first animation's rate)
		cycle += (clock - view_as<float>(a[REC_SIM])) * rate;
		if (loops) cycle -= float(RoundToFloor(cycle));
		else if (cycle > 1.0) cycle = 1.0;
	}
	serverCycle = cycle;
	fromStart = false;
	if (entity > MaxClients)
		fromStart = CommonClientCycle(entity, pm, clock, a, b, haveB, cycle, rate);
	return true;
}

// Cycles per second of the sequence in record a: measured between records of the same run, else
// the model's rate times the playback rate.
float SequenceRate(int entity, PoseModel pm, const int a[REC_SIZE], const int b[REC_SIZE], bool haveB)
{
	int seq = a[REC_SEQ];
	bool loops = SeqLoops(pm, seq);
	float rate = -1.0;
	if (haveB && b[REC_SEQ] == seq && b[REC_PARITY] == a[REC_PARITY])
		rate = CycleRate(a, b, loops);
	if (rate < 0.0)
	{
		int p[REC_SIZE], q[REC_SIZE];
		bool haveQ;
		float f;
		if (FindRecordPair(entity, view_as<float>(a[REC_SIM]) - 0.001, p, q, haveQ, f)
			&& p[REC_SEQ] == seq && p[REC_PARITY] == a[REC_PARITY])
			rate = CycleRate(p, a, loops);
	}
	if (rate < 0.0)
	{
		if (pm.seqInfo == null || seq < 0 || seq >= pm.seqInfo.Length)
			return 0.0;
		float info[SI_SIZE];
		pm.seqInfo.GetArray(seq, info);
		rate = info[SI_RATE] * view_as<float>(a[REC_RATE]);
	}
	return rate;
}

// Computes the main sequence and cycle the shooter's client drew (players: client clock, or the
// delayed clock for movement sequences; commons / witches: from the start time)
// and stores them for the BacktrackEntity post hook, which writes them over the engine's.
void PrepareClientClockMain(int entity, float target)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return;
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float clock0 = ClientClock(entity, target, lerp);
	bool player = entity <= MaxClients;

	// 1. client: frame at the client clock
	int a[REC_SIZE];
	int seq0;
	float cycle0, own0, rate0;
	bool fromStart0;
	g_bCcClamped = false;
	g_iCcRule = 0;
	if (!ComputeClockFrame(entity, pm, clock0, seq0, cycle0, own0, rate0, fromStart0, a))
		return;
	int ccRule = fromStart0 ? g_iCcRule : 0;
	float ccEntry = g_fCcEntry, ccPbr = g_fCcPbr, ccModelRate = g_fCcModelRate;
	bool ccClamped = g_bCcClamped;

	// players in a movement sequence: the client chose it and plays it from the velocity of the
	// position it draws, which is its interpolation (lerp in whole ticks) behind its clock
	float ti = g_fTick;
	int lerpTicks = RoundToFloor(0.5 + lerp / ti);
	float clientClock = clock0;
	bool moving = false;
	float runLag = 0.0, runRestart = 0.0;
	if (player && lerpTicks > 0 && IsMoveSeq(pm, seq0))
	{
		// The client plays a movement sequence on its own clock from when the change reached it; only
		// its rate comes from the position it draws (its speed estimate). The Hunter's leap is the
		// exception: the client restarts Pounce_01 its interpolation (lerp in whole ticks) after it
		// arrives.
		moving = true;
		if (SeqKind(pm, seq0) & SK_POUNCE)
		{
			int am[REC_SIZE], seqM;
			float cycM, ownM, rateM;
			bool fsM;
			float clockM = clock0 - float(lerpTicks) * ti;
			if (ComputeClockFrame(entity, pm, clockM, seqM, cycM, ownM, rateM, fsM, am) && seqM == seq0)
			{
				cycle0 = cycM; own0 = ownM; rate0 = rateM; fromStart0 = fsM; a = am;
				clientClock = clockM;
			}
			else
				moving = false;
		}
		else
		{
			// the client restarted the run when its start reached it, later than the server
			runLag = ClientRunLag(entity, pm, seq0, a, clock0, runRestart);
			if (runLag != 0.0)
			{
				cycle0 -= runLag;
				if (SeqLoops(pm, seq0))
					cycle0 -= float(RoundToFloor(cycle0));
				else if (cycle0 < 0.0)
					cycle0 = 0.0;
			}
		}
	}

	if (!g_bCycleSaved[entity])
	{
		g_fSavedCycle[entity] = GetEntDataFloat(entity, g_iOffCycle);
		g_bCycleSaved[entity] = true;
	}
	g_iSavedSeq[entity] = GetEntData(entity, g_iOffSequence);
	g_bSeqSaved[entity] = true;
	g_iClockSeq[entity] = seq0;
	g_fClockCycle[entity] = cycle0;
	g_bClockMain[entity] = true;

	if (g_iDebug > 0)
	{
		float start0 = view_as<float>(a[REC_SEQSTART]);
		// the server: what the engine rewound to (record at the target time)
		int ea[REC_SIZE], eb[REC_SIZE];
		bool eHaveB;
		float eFrac;
		float engineCycle = -1.0;
		int engineSeq = -1;
		if (FindRecordPair(entity, target, ea, eb, eHaveB, eFrac))
		{
			engineSeq = ea[REC_SEQ];
			engineCycle = view_as<float>(ea[REC_CYCLE]);
			if (eHaveB && eb[REC_SEQ] == ea[REC_SEQ] && eb[REC_PARITY] == ea[REC_PARITY])
				engineCycle = LerpCycle(engineCycle, view_as<float>(eb[REC_CYCLE]), eFrac, SeqLoops(pm, ea[REC_SEQ]));
		}
		bool sameSeq = (engineSeq == seq0 && engineCycle >= 0.0);
		float diff = 0.0;                  // server - client, in cycles (wrapped for looping sequences)
		if (sameSeq)
		{
			diff = engineCycle - cycle0;
			// the client's cycle wraps for looping sequences, and for common infected also for finished
			// non-looping ones (restarted from the start time)
			if (SeqLoops(pm, seq0) || (!player && fromStart0))
			{
				if (diff > 0.5) diff -= 1.0;
				else if (diff < -0.5) diff += 1.0;
			}
		}
		char eName[SEQ_NAME_LEN + 64], name0[SEQ_NAME_LEN + 64];
		SeqLabel(pm, engineSeq, eName, sizeof(eName));
		SeqLabel(pm, seq0, name0, sizeof(name0));
		Dbg(entity, "[posesync] ent %d (%s) cycles:", entity, player ? "player" : "common");
		Dbg(entity, "[posesync]   Cycles (Server): %.3f  %s, at the engine's target time %.3f", engineCycle, eName, target);
		if (moving)
		{
			if (SeqKind(pm, seq0) & SK_POUNCE)
				Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at %.3f = client clock %.3f - interpolation %d ticks (the client restarts the leap from the position it draws)",
					cycle0, name0, clientClock, clock0, lerpTicks);
			else
				Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f = target + lerp %.3f + %d tick (it plays it on its own clock)",
					cycle0, name0, clientClock, lerp, CLIENT_CLOCK_TICKS);
			if (runLag != 0.0)
				Dbg(entity, "[posesync]   the client restarted this run %.0f ms after the server (when the snapshot with its start reached it): %.3f cycles behind for the whole run",
					runRestart * 1000.0, runLag);
		}
		else if (player)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f = target + lerp %.3f + %d tick",
				cycle0, name0, clock0, lerp, CLIENT_CLOCK_TICKS);
		else if (fromStart0 && ccRule == 1)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f: came into your view at %.3f, %.2f s after it started (%.3f): (%.3f - %.3f) x %.3f/s model rate + (%.3f - %.3f) x %.3f/s (playback rate %.2f) (server's own %.3f)",
				cycle0, name0, clock0, ccEntry, ccEntry - start0, start0, ccEntry, start0, ccModelRate, clock0, ccEntry, rate0, ccPbr, own0);
		else if (fromStart0 && ccRule == 3)
		{
			char again[96];
			int shr = g_iShooter;
			if (shr > 0 && shr < PTX_MAX && g_fTxFirst[shr][entity] > 0.0 && ccEntry - g_fTxFirst[shr][entity] > 0.0005)
				FormatEx(again, sizeof(again), " (first at %.3f, sent again as new until your client confirmed it)", g_fTxFirst[shr][entity]);
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f: came into your view at %.3f%s, %.2f s after it started (under 1 s), so your client started it at cycle 0 then: (%.3f - %.3f) x %.3f/s",
				cycle0, name0, clock0, ccEntry, again, ccEntry - start0, clock0, ccEntry, rate0);
		}
		else if (fromStart0 && ccRule == 4)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f: the new start time %.3f was first sent to your client at %.3f (%.0f ms later), where it started it at cycle 0: (%.3f - %.3f) x %.3f/s (server's own %.3f)",
				cycle0, name0, clock0, start0, ccEntry, (ccEntry - start0) * 1000.0, clock0, ccEntry, rate0, own0);
		else if (fromStart0 && ccRule == 5)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f: the start time %.3f was first sent to your client at %.3f (%.2f s later): (%.3f - %.3f) x %.3f/s model rate + (%.3f - %.3f) x %.3f/s (server's own %.3f)",
				cycle0, name0, clock0, start0, ccEntry, ccEntry - start0, ccEntry, start0, ccModelRate, clock0, ccEntry, rate0, own0);
		else if (fromStart0 && ccRule == 2)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f = target + lerp %.3f: 0.15 (the client starts this one at a random 0 - 0.3) + (%.3f - start %.3f) x %.3f/s (server's own %.3f)",
				cycle0, name0, clock0, lerp, clock0, start0, rate0, own0);
		else if (fromStart0)
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f = target + lerp %.3f: (%.3f - start %.3f) x %.3f/s (server's own %.3f)",
				cycle0, name0, clock0, lerp, clock0, start0, rate0, own0);
		else
			Dbg(entity, "[posesync]   Cycles (Client): %.3f  %s, at the client clock %.3f = target + lerp %.3f (server's own, no start time)",
				cycle0, name0, clock0, lerp);
		// when the server first sent this start time to the shooter (for comparing with cl_showanimstate)
		int shx = g_iShooter;
		if (!player && fromStart0 && shx > 0 && shx < PTX_MAX && FloatAbs(g_fTxLastStart[shx][entity] - start0) < 0.0005
			&& g_fTxSeen[shx][entity] > 0.0)
			Dbg(entity, "[posesync]   start time %.3f was first sent to your client in the snapshot of %.3f (%.0f ms later)",
				start0, g_fTxSeen[shx][entity], (g_fTxSeen[shx][entity] - start0) * 1000.0);
		if (!player && ccClamped)
			Dbg(entity, "[posesync]   Note: this common's server updates were more than 0.2 s apart, so its own animation lost time (the server plays at most 0.2 s per update); the rate is taken over the time it played");
		if (sameSeq && rate0 > 0.0)
			Dbg(entity, "[posesync]   Server - client: %s%.3f = %.0f ms of animation %s the client",
				diff >= 0.0 ? "+" : "", diff, FloatAbs(diff) / rate0 * 1000.0, diff > 0.0 ? "ahead of" : (diff < 0.0 ? "behind" : "level with"));
		else if (!sameSeq)
			Dbg(entity, "[posesync]   Server - client: different animations");
		if (player)
			Dbg(entity, "[posesync]   Calculation: players take the client's frame (%.0f ms %s the engine's target time)",
				FloatAbs(clientClock - target) * 1000.0, clientClock >= target ? "after" : "before");
		else
			Dbg(entity, "[posesync]   Calculation: the client's frame is used");
		Dbg(entity, "[posesync]   Cycles (Updated server value): %.3f  %s, used for the hitboxes", cycle0, name0);
	}
}

// Keeps every overlay layer once per rewind, before the plugin changes any of them.
void SaveAllLayers(int entity)
{
	if (g_iTransCount[entity] > 0)
		return;
	int layerCount;
	LayerAddr(entity, 0, layerCount);
	if (layerCount > MAX_LAYERS_SAVED)
		layerCount = MAX_LAYERS_SAVED;
	int cnt;   // LayerAddr writes the real count into its out-parameter, which must not undo the cap
	for (int i = 0; i < layerCount; i++)
		SaveLayer(entity, i, LayerAddr(entity, i, cnt));
	g_iTransCount[entity] = layerCount;
}

// Players: overlay layers (gestures, aim layers) from the records at the client clock.
bool ApplyClientClockLayers(int entity, float target)
{
	if (!g_bLayersOK)
		return false;
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return false;
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float clock = ClientClock(entity, target, lerp);

	int a[REC_SIZE], b[REC_SIZE];
	bool haveB;
	float frac;
	if (!FindRecordPair(entity, clock, a, b, haveB, frac))
		return false;

	int layerCount;
	LayerAddr(entity, 0, layerCount);
	int n = a[REC_NLAYERS];
	if (n > layerCount) n = layerCount;
	if (n <= 0)
		return false;

	SaveAllLayers(entity);
	int changed = 0;
	for (int k = 0; k < n; k++)
	{
		Address addr = LayerAddr(entity, k, layerCount);
		if (addr == Address_Null)
			continue;
		int o = REC_LAYERS + k * REC_LSTRIDE;
		int seq = a[o + 1];
		float cycle = view_as<float>(a[o + 2]);
		float weight = view_as<float>(a[o + 3]);
		if (haveB && b[REC_NLAYERS] > k && b[o + 1] == seq)
		{
			cycle = LerpCycle(cycle, view_as<float>(b[o + 2]), frac, SeqLoops(pm, seq));
			weight += (view_as<float>(b[o + 3]) - weight) * frac;
		}
		if (LoadI(addr, LAYER_SEQUENCE) != seq || FloatAbs(view_as<float>(LoadI(addr, LAYER_CYCLE)) - cycle) > 0.0005
			|| FloatAbs(view_as<float>(LoadI(addr, LAYER_WEIGHT)) - weight) > 0.0005)
			changed++;
		StoreI(addr, LAYER_FLAGS, a[o]);
		StoreI(addr, LAYER_SEQUENCE, seq);
		StoreI(addr, LAYER_CYCLE, cycle);
		StoreI(addr, LAYER_PREVCYCLE, cycle);
		StoreI(addr, LAYER_WEIGHT, weight);
		StoreI(addr, LAYER_ORDER, a[o + 4]);
	}
	if (g_iDebug > 0 && changed > 0)
		Dbg(entity, "[posesync] ent %d: %d overlay layer(s) moved to the client clock %.3f", entity, changed, clock);
	return true;
}

// Common infected / witch cycle the way client.dll computes it (0x103146c4): when
// m_sequenceStartTime arrives, cycle = (curtime - m_sequenceStartTime) * cycle rate, then the
// client plays on from there. The server's own cycle runs about one NextBot update (0.1 s) ahead
// of that. The rate is taken from the server's records (it includes the blend of a 3x3 run and the
// playback rate); the model's rate is the fallback. Returns false without a start time.
bool CommonClientCycle(int entity, PoseModel pm, float clock, const int a[REC_SIZE], const int b[REC_SIZE], bool haveB, float &cycle, float &rateOut)
{
	float start = view_as<float>(a[REC_SEQSTART]);
	if (start < 0.0)
		return false;
	int seq = a[REC_SEQ];
	bool loops = SeqLoops(pm, seq);

	float rate = -1.0;
	if (haveB && b[REC_SEQ] == seq && b[REC_SEQSTART] == a[REC_SEQSTART])
		rate = CycleRate(a, b, loops);
	if (rate < 0.0)
	{
		int p[REC_SIZE], q[REC_SIZE];
		bool haveQ;
		float f;
		if (FindRecordPair(entity, view_as<float>(a[REC_SIM]) - 0.001, p, q, haveQ, f)
			&& p[REC_SEQ] == seq && p[REC_SEQSTART] == a[REC_SEQSTART])
			rate = CycleRate(p, a, loops);
	}
	if (rate < 0.0)
	{
		if (pm.seqInfo == null || seq < 0 || seq >= pm.seqInfo.Length)
			return false;
		float info[SI_SIZE];
		pm.seqInfo.GetArray(seq, info);
		rate = info[SI_RATE] * view_as<float>(a[REC_RATE]);
	}

	// client.dll (0x10314728): ACT_TERROR_ATTACK_CONTINUOUSLY, _LOW_CONTINUOUSLY, _DOOR_CONTINUOUSLY and
	// ACT_TERROR_REACH_THROUGH_DOOR start at RandomFloat(0, 0.3) on the client, cycle 0 on the
	// server. The value is never sent, so the expected 0.15 halves the worst case.
	float base = 0.0;
	g_iCcRule = 0;
	g_fCcPbr = view_as<float>(a[REC_RATE]);
	g_fCcModelRate = rate;
	if (IsRandomStartAct(pm, seq))
	{
		base = 0.15;
		g_iCcRule = 2;
	}
	float elapsed = clock - start;
	if (elapsed < 0.0)
		elapsed = 0.0;
	float c = base + elapsed * rate;

	// Came into the shooter's view with a start time new to its client. client.dll (0x103146c4), when
	// a new m_sequenceStartTime arrives: elapsed = now - start, but 0 when the sequence started less
	// than 1 s ago and the common did not go dormant (out of view) within the last 1 s; the frame is
	// elapsed x the model's cycle rate, without the playback rate (0.9 - 1.1 per entity for alert
	// idles, speed based while moving), and it plays on from there with the playback rate. Seen live,
	// "now" is when the snapshot with the new start time reached it (below). Coming into view, a sequence that started under 1 s ago (and a
	// common that had been out of view for over 1 s) starts at cycle 0 on arrival, and an older one
	// at (arrival - start) x the model's rate.
	int sh = g_iShooter;
	if (g_iCcRule == 0 && sh > 0 && sh < PTX_MAX && g_bTxRecalc[sh][entity]
		&& FloatAbs(g_fTxEntryStart[sh][entity] - start) < 0.0005)
	{
		float entry = g_fTxEntry[sh][entity];
		float pbr = g_fCcPbr;
		if (entry > start + 0.0001 && entry < clock && pbr > 0.01)
		{
			float modelRate = rate / pbr;
			if (entry > g_fTxDormant[sh][entity] + 1.0 && start + 1.0 > entry)
			{
				c = (clock - entry) * rate;
				g_iCcRule = 3;
			}
			else
			{
				c = (entry - start) * modelRate + (clock - entry) * rate;
				g_iCcRule = 1;
			}
			g_fCcEntry = entry;
			g_fCcModelRate = modelRate;
		}
	}
	// Seen live: the client applies the same rule (0x103146c4) when the snapshot with the new start
	// time reaches it, so "now" is when that snapshot was sent, not the start time itself. The
	// client's clock runs on the snapshot times it receives, so the server time of that first
	// snapshot is the client's time for it.
	if (g_iCcRule == 0 && sh > 0 && sh < PTX_MAX && FloatAbs(g_fTxLastStart[sh][entity] - start) < 0.0005)
	{
		float arrival = g_fTxSeen[sh][entity];
		float pbr = g_fCcPbr;
		if (arrival > start + 0.0001 && arrival < clock && pbr > 0.01)
		{
			float modelRate = rate / pbr;
			if (arrival > g_fTxDormant[sh][entity] + 1.0 && start + 1.0 > arrival)
			{
				c = (clock - arrival) * rate;
				g_iCcRule = 4;
			}
			else
			{
				c = (arrival - start) * modelRate + (clock - arrival) * rate;
				g_iCcRule = 5;
			}
			g_fCcEntry = arrival;
			g_fCcModelRate = modelRate;
		}
	}
	// client.dll (0x10314688): when a non-looping sequence finishes and the server has not sent a
	// new one, the client restarts it from 0 (start time = now). The server holds it at 1 until its
	// next update picks something else, so on the client it wraps like a loop.
	c -= float(RoundToFloor(c));
	cycle = c;
	rateOut = rate;
	return true;
}

// Sequences client.dll starts at a random cycle on common infected.
bool IsRandomStartAct(PoseModel pm, int seq)
{
	return (SeqKind(pm, seq) & SK_RANDOM) != 0;
}

// Activities client.dll starts at a random cycle on common infected.
bool ActIsRandomStart(const char[] act)
{
	return StrEqual(act, "ACT_TERROR_ATTACK_CONTINUOUSLY", false) || StrEqual(act, "ACT_TERROR_ATTACK_LOW_CONTINUOUSLY", false)
		|| StrEqual(act, "ACT_TERROR_ATTACK_DOOR_CONTINUOUSLY", false) || StrEqual(act, "ACT_TERROR_REACH_THROUGH_DOOR", false);
}

// Cycles per second between two records of the same sequence run, -1 if unusable.
// The server advances an entity's animation by at most 0.2 s per update (StudioFrameAdvance,
// MAX_ANIMTIME_INTERVAL), so when NextBot updates of a common infected are more than 0.2 s apart
// (nb_update_framelimit under load) its own cycle loses the rest; the client plays on in real time.
// The rate is taken over the time the server actually played.
float CycleRate(const int older[REC_SIZE], const int newer[REC_SIZE], bool loops)
{
	float dt = view_as<float>(newer[REC_SIM]) - view_as<float>(older[REC_SIM]);
	if (dt <= 0.0001)
		return -1.0;
	if (dt > 0.2)
	{
		dt = 0.2;
		g_bCcClamped = true;
	}
	float dc = view_as<float>(newer[REC_CYCLE]) - view_as<float>(older[REC_CYCLE]);
	if (dc < 0.0)
	{
		if (!loops)
			return -1.0;
		dc += 1.0;
	}
	if (dc <= 0.0)
		return -1.0;      // stopped (end of a non-looping sequence): use the model's rate
	return dc / dt;
}

// ---------------------------------------------------------------------------
// sm_posesync_profile: measures the plugin's own CPU time (recording every tick, rewinding per
// lag compensated entity) for a number of seconds and prints it.
// ---------------------------------------------------------------------------

// sm_posesync_profile [seconds]: start a measurement.
Action Cmd_Profile(int client, int args)
{
	float secs = 10.0;
	if (args >= 1)
	{
		char buf[16];
		GetCmdArg(1, buf, sizeof(buf));
		secs = StringToFloat(buf);
		if (secs < 1.0) secs = 1.0;
		if (secs > 120.0) secs = 120.0;
	}
	if (g_hProf == null)
		g_hProf = new Profiler();
	g_fProfRecord = 0.0;
	g_fProfRewind = 0.0;
	g_iProfRecords = 0;
	g_iProfTicks = 0;
	g_iProfRewinds = 0;
	g_iProfLastTick = 0;
	g_fProfEnd = GetEngineTime() + secs;
	g_bProfiling = true;
	ReplyToCommand(client, "[posesync] profiling for %.0f s, the result goes to the server console.", secs);
	return Plugin_Handled;
}

// Prints the measurement (from OnGameFrame when the time is up).
void FinishProfile()
{
	g_bProfiling = false;
	int ticks = g_iProfTicks > 0 ? g_iProfTicks : 1;
	int recs = g_iProfRecords > 0 ? g_iProfRecords : 1;
	int rews = g_iProfRewinds > 0 ? g_iProfRewinds : 1;
	PrintToServer("[posesync] profile: recording %.1f us per tick (%d calls, %.2f us each, %d ticks); rewinding %.1f us per rewound entity (%d rewinds, %.2f ms total)",
		g_fProfRecord * 1000000.0 / ticks, g_iProfRecords, g_fProfRecord * 1000000.0 / recs, g_iProfTicks,
		g_fProfRewind * 1000000.0 / rews, g_iProfRewinds, g_fProfRewind * 1000.0);
	PrintToServer("[posesync] profile: one server tick is %.0f us", g_fTick * 1000000.0);
}

// ---------------------------------------------------------------------------
// Common hold: common infected / witch position as the client draws it
//
// A common's simulation time (and with it a new position sample on the client) only moves on its
// NextBot updates, about every 0.1 s. The client has the updates up to its clock (the command's
// tick_count) and draws at that clock minus its interpolation. With an interpolation under 0.1 s it
// often draws past the newest update it has. C_BaseEntity's interpolated variables then extrapolate
// only a value that arrived in the latest packet (client.dll 0x1003745c: m_flLastNetworkedTime >= the
// last packet's time stamp), which a common's update never is at that point, so the client holds
// the newest update. The engine instead interpolates between that update and the next one, which the
// client had not received.
// ---------------------------------------------------------------------------

// Simulation time of the newest update the shooter's client had (the command's tick_count, i.e. the
// engine's target time plus the shooter's lerp, in whole ticks), relative to a draw time.
float ClientNewestUpdate(int entity, float drawT)
{
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float clock = (g_bAnimTarget[entity] ? g_fAnimTarget[entity] : drawT) + lerp;
	int n;
	int idx = FindRecIndex(entity, clock, n);
	if (idx == -1)
		return -1.0;
	return view_as<float>(g_hHistory[entity].Get(idx, REC_SIM));
}

// Puts back the engine's rewound origin and angles before FinishLagCompensation (it restores the
// present plus any offset from where it left the entity).
void UndoHold(int entity)
{
	if (!g_bHeld[entity])
		return;
	g_bHeld[entity] = false;
	if (!IsValidEntity(entity))
		return;
	float org[3], ang[3];
	for (int i = 0; i < 3; i++)
	{
		org[i] = g_fHeldEngOrg[entity * 3 + i];
		ang[i] = g_fHeldEngAng[entity * 3 + i];
	}
	SDKCall(g_hSetAbsOrigin, entity, org);
	SDKCall(g_hSetAbsAngles, entity, ang);
	// as the engine left it (its FinishLagCompensation then puts the present one back)
	SetEntDataFloat(entity, g_iOffSimTime, g_fHeldSim[entity], true);
}

// ---------------------------------------------------------------------------
// Debug: where the shooter's client drew a common compared with the engine's interpolated position
// (see MoveToClientPosition).
// ---------------------------------------------------------------------------
void DebugCommonExtrapolation(int entity, float target, float engineTarget)
{
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	float clock = engineTarget + lerp;

	int n[REC_SIZE], nb[REC_SIZE], a[REC_SIZE], b[REC_SIZE];
	bool haveNB, haveB;
	float f;
	if (!FindRecordPair(entity, clock, n, nb, haveNB, f))          // newest update the client has
		return;
	float sn = view_as<float>(n[REC_SIM]);
	if (target <= sn)
	{
		Dbg(entity, "[posesync] ent %d (common): the client interpolates it like the engine (newest update it has %.3f, draw time %.3f)", entity, sn, target);
		return;
	}
	if (!FindRecordPair(entity, target, a, b, haveB, f))
		return;
	float engine[3], held[3];
	for (int i = 0; i < 3; i++)
	{
		float oa = view_as<float>(a[REC_ORG + i]);
		engine[i] = haveB ? oa + (view_as<float>(b[REC_ORG + i]) - oa) * f : oa;
		held[i] = view_as<float>(n[REC_ORG + i]);
	}
	Dbg(entity, "[posesync] ent %d (common): draw time %.3f is %.0f ms past the newest update the client has (%.3f); the client holds it there, %.1f units from the engine's interpolated position%s",
		entity, target, (target - sn) * 1000.0, sn, GetVectorDistance(held, engine), g_bCanMove ? " (moved there)" : "");
}

// ---------------------------------------------------------------------------
// What the shooter's client interpolates
//
// C_BaseEntity::m_iv_vecOrigin is a CInterpolatedVar<Vector> with type LATCH_SIMULATION_VAR (no
// INTERPOLATE_LINEAR_ONLY), so client.dll (0x1004aa10) draws an origin between the two samples around
// the draw time with a Hermite spline through a third, older one (0x10048240, the older sample time
// fixed up to the same spacing, 0x100435e0), and linearly only when it has two. Past its newest
// sample it holds it (it extrapolates only a value from the very latest packet). Its samples are the
// states it received: a player's every tick only when cl_updaterate matches the tick rate, a common's
// every NextBot update.
//
// C_BaseEntity::EstimateAbsVelocity (0x1004c230) is m_iv_vecOrigin.GetDerivative_SmoothVelocity
// (0x10049780) over the same samples: with three, the Hermite derivative (0x10047a90: the velocity of
// the older segment lerped to the newer one's), with two the newer segment's velocity, and 0 when the
// draw time is past the newest sample. The animstate's move blend, the Hunter's pounce blend and a
// common's move blend come from it, so they are built here from the client's samples too.
// ---------------------------------------------------------------------------

// client-side samples around a draw time: the oldest one newer than it, and up to two at or before it
enum struct CSamples
{
	bool haveNewer;
	float tN;
	float oN[3];
	int iN;                 // ring index of its record
	int nBelow;
	float tB[2];
	float oB[6];
	int iB[2];
	bool tracked;           // built from the snapshots the client was sent (players)
}

#define CI_NONE     0
#define CI_LINEAR   1
#define CI_HERMITE  2
#define CI_HOLD     3       // past the newest sample: held there
#define CI_OLDEST   4       // before the oldest sample: drawn there

// called for each client a player is about to be sent to
public Action Hook_PlayerTransmit(int entity, int client)
{
	if (client < 1 || client >= PTX_MAX || entity < 1 || entity >= PTX_MAX || client == entity || !g_bHuman[client])
		return Plugin_Continue;
	int tick = GetGameTickCount();
	// the smallest gap is 0 or 1; once 0 has been seen, or 1 has been seen many times, it is known
	if (g_iTxRecGap > 0 && g_iTxGapSamples < 2000 && g_hHistory[entity] != null && g_iCount[entity] > 0)
	{
		int gap = tick - g_hHistory[entity].Get(g_iHead[entity], REC_TICK);
		if (gap >= 0 && gap < g_iTxRecGap)
			g_iTxRecGap = gap;
		if (gap == 1)
			g_iTxGapSamples++;
	}
	int head = g_iPlTxHead[client][entity];
	if (g_iPlTxCount[client][entity] > 0 && g_iPlTx[client][entity * PTX_RING + head] == tick)
		return Plugin_Continue;
	// entering the client's snapshots (spawned in view, materialized, back in its PVS): the client
	// makes the player new and resets its interpolation (see FindResetWindow)
	if (g_iPlTxCount[client][entity] == 0 || float(tick - g_iPlTx[client][entity * PTX_RING + head]) * g_fTick > TX_GAP)
	{
		g_iPlTxEnter[client][entity] = tick;
		g_bPlTxNew[client][entity] = g_iPlTxCount[client][entity] == 0;
	}
	head = (g_iPlTxCount[client][entity] == 0) ? 0 : (head + 1) % PTX_RING;
	g_iPlTx[client][entity * PTX_RING + head] = tick;
	g_iPlTxHead[client][entity] = head;
	if (g_iPlTxCount[client][entity] < PTX_RING)
		g_iPlTxCount[client][entity]++;
	return Plugin_Continue;
}

// The shooter's client clock for a draw time (the newest state it can have).
float SampleClock(int entity, float drawT)
{
	float cvarLerp;
	float lerp = GetShooterLerp(g_iShooter, cvarLerp);
	return (g_bAnimTarget[entity] ? g_fAnimTarget[entity] : drawT) + lerp;
}

// Collects the client's samples of an entity's origin around drawT, from the records it received by
// its clock. Players: the newest record made by each server tick the shooter was sent the player in.
// Common infected: every record (one per NextBot update, which every snapshot rate above 10/s
// carries). Records from a sequence change without a new simulation time are not samples. A no-interp
// reset clears the client's history, so nothing older than it is used.
bool BuildClientSamples(int entity, int shooter, float clock, float drawT, CSamples cs)
{
	cs.haveNewer = false;
	cs.nBelow = 0;
	cs.tracked = false;
	ArrayList h = g_hHistory[entity];
	if (h == null || g_iCount[entity] == 0 || shooter < 1 || shooter > MaxClients || !g_bHuman[shooter])
		return false;
	int size = g_iRingSize, count = g_iCount[entity];
	int model = ModelIndexOf(entity);
	bool tracked = entity <= MaxClients && entity < PTX_MAX && shooter < PTX_MAX && g_iPlTxCount[shooter][entity] > 0;
	cs.tracked = tracked;
	int clockTick = RoundToNearest(clock / g_fTick);
	int r = g_iHead[entity], rn = 0;
	int ti = tracked ? g_iPlTxHead[shooter][entity] : 0, tn = 0, tcount = tracked ? g_iPlTxCount[shooter][entity] : 0;
	float last = -1.0;
	bool haveLast = false;
	while (cs.nBelow < 2 && rn < count)
	{
		if (tracked)
		{
			int limit = -1;
			while (tn < tcount)
			{
				int tk = g_iPlTx[shooter][entity * PTX_RING + ti];
				ti = (ti - 1 + PTX_RING) % PTX_RING;
				tn++;
				if (tk <= clockTick)
				{
					limit = tk;
					break;
				}
			}
			if (limit < 0)
				break;
			while (rn < count && (h.Get(r, REC_TICK) > limit || !h.Get(r, REC_REAL)))
			{
				r = (r - 1 + size) % size;
				rn++;
			}
		}
		else
		{
			while (rn < count && (!h.Get(r, REC_REAL) || view_as<float>(h.Get(r, REC_SIM)) > clock + 0.0001))
			{
				r = (r - 1 + size) % size;
				rn++;
			}
		}
		if (rn >= count)
			break;
		float sim = view_as<float>(h.Get(r, REC_SIM));
		if (haveLast && sim >= last - 0.00001)
		{
			// the same state again (no newer record between two snapshots)
			if (!tracked)
			{
				r = (r - 1 + size) % size;
				rn++;
			}
			continue;
		}
		if (h.Get(r, REC_MODEL) != model)
			break;
		haveLast = true;
		last = sim;
		if (sim > drawT + 0.00001)
		{
			cs.haveNewer = true;
			cs.tN = sim;
			cs.iN = r;
			for (int k = 0; k < 3; k++)
				cs.oN[k] = view_as<float>(h.Get(r, REC_ORG + k));
		}
		else
		{
			int b = cs.nBelow++;
			cs.tB[b] = sim;
			cs.iB[b] = r;
			for (int k = 0; k < 3; k++)
				cs.oB[b * 3 + k] = view_as<float>(h.Get(r, REC_ORG + k));
		}
		if (entity <= MaxClients && h.Get(r, REC_RESET))
			break;      // the client's history starts here
		if (!tracked)
		{
			r = (r - 1 + size) % size;
			rn++;
		}
	}
	return cs.haveNewer || cs.nBelow > 0;
}

// Lerp_Hermite (mathlib): p0 the older sample (time fixed up), p1 / p2 the two around the time.
float HermiteVal(float t, float p0, float p1, float p2)
{
	float t2 = t * t, t3 = t2 * t;
	return p1 * (2.0 * t3 - 3.0 * t2 + 1.0) + p2 * (-2.0 * t3 + 3.0 * t2)
		+ (p1 - p0) * (t3 - 2.0 * t2 + t) + (p2 - p1) * (t3 - t2);
}

// Origin and EstimateAbsVelocity the client has at time t from its samples. Returns a CI_* mode.
int ClientInterp(CSamples cs, float t, float pos[3], float vel[3], float &frac)
{
	frac = 0.0;
	vel[0] = 0.0; vel[1] = 0.0; vel[2] = 0.0;
	if (cs.nBelow == 0)
	{
		if (!cs.haveNewer)
			return CI_NONE;
		pos[0] = cs.oN[0]; pos[1] = cs.oN[1]; pos[2] = cs.oN[2];
		return CI_OLDEST;
	}
	if (!cs.haveNewer)
	{
		pos[0] = cs.oB[0]; pos[1] = cs.oB[1]; pos[2] = cs.oB[2];
		return CI_HOLD;
	}
	float dt = cs.tN - cs.tB[0];
	frac = (dt > 0.0001) ? (t - cs.tB[0]) / dt : 0.0;
	if (frac > 2.0)
		frac = 2.0;
	if (cs.nBelow == 2 && cs.tB[0] - cs.tB[1] > 0.0001)
	{
		// TimeFixup_Hermite: the oldest sample moved to the same spacing as the newer pair
		float dt2 = cs.tB[0] - cs.tB[1];
		float p0[3], p0t = cs.tB[1];
		for (int k = 0; k < 3; k++)
			p0[k] = cs.oB[3 + k];
		if (FloatAbs(dt - dt2) > 0.0001 && dt2 > 0.0001)
		{
			float f = dt / dt2;
			for (int k = 0; k < 3; k++)
				p0[k] = cs.oB[k] + (p0[k] - cs.oB[k]) * f;
			p0t = cs.tB[0] - dt;
		}
		float pdt = cs.tB[0] - p0t;
		for (int k = 0; k < 3; k++)
		{
			pos[k] = HermiteVal(frac, p0[k], cs.oB[k], cs.oN[k]);
			float prevVel = (pdt > 0.0001) ? (cs.oB[k] - p0[k]) / pdt : 0.0;
			float curVel = (dt > 0.0001) ? (cs.oN[k] - cs.oB[k]) / dt : 0.0;
			vel[k] = prevVel + (curVel - prevVel) * frac;
		}
		return CI_HERMITE;
	}
	for (int k = 0; k < 3; k++)
	{
		pos[k] = cs.oB[k] + (cs.oN[k] - cs.oB[k]) * frac;
		vel[k] = (dt > 0.0001) ? (cs.oN[k] - cs.oB[k]) / dt : 0.0;
	}
	return CI_LINEAR;
}

// The shooter's client's velocity estimate at draw time t with its clock at 'clock' (false: no
// samples). mode = how it was worked out (CI_*).
int ClientVelocityClock(int entity, float clock, float t, float vel[3])
{
	CSamples cs;
	if (!BuildClientSamples(entity, g_iShooter, clock, t, cs))
		return CI_NONE;
	float pos[3], frac;
	return ClientInterp(cs, t, pos, vel, frac);
}

// ... at an earlier draw time t (its clock then: t + lerp).
bool ClientVelocityAt(int entity, float t, float lerp, float vel[3])
{
	return ClientVelocityClock(entity, t + lerp, t, vel) != CI_NONE;
}

// ... at the draw time of this rewind.
bool ClientVelocity(int entity, float drawT, float vel[3], int &mode)
{
	mode = ClientVelocityClock(entity, SampleClock(entity, drawT), drawT, vel);
	return mode != CI_NONE;
}

static const char g_sCiMode[][] = { "none", "linear between", "Hermite spline through", "held at", "drawn at" };

// Puts a rewound player or common where the shooter's client drew it, when that is not where the
// engine's linear interpolation between every record left it: a Hermite curve instead of a line, the
// snapshots the client actually got, or its newest update held. Saves the engine's origin and angles
// for UndoHold. Returns true if it moved the entity.
bool MoveToClientPosition(int entity, float drawT)
{
	if (g_bHeld[entity] || g_hHistory[entity] == null || g_iCount[entity] < 2)
		return false;
	if (GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") != -1)
		return false;
	CSamples cs;
	float clock = SampleClock(entity, drawT);
	if (!BuildClientSamples(entity, g_iShooter, clock, drawT, cs))
		return false;
	float org[3], vel[3], frac;
	int mode = ClientInterp(cs, drawT, org, vel, frac);
	if (mode == CI_NONE)
		return false;

	float cur[3], ang[3], newAng[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", cur);
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
	newAng = ang;
	// a common's facing: the engine's interpolation matches the client's, except at a held sample
	if (entity > MaxClients && g_iOffAbsRotation > 0 && (mode == CI_HOLD || mode == CI_OLDEST))
		newAng[1] = view_as<float>(g_hHistory[entity].Get(mode == CI_HOLD ? cs.iB[0] : cs.iN, REC_AYAW));
	float d[3];
	SubtractVectors(org, cur, d);
	float dist = GetVectorLength(d);
	if (dist < 0.05 && FloatAbs(AngleDiff(newAng[1], ang[1])) < 0.01)
		return false;
	if (dist > 64.0)
		return false;       // not a gap between two samples (a teleport): leave the engine's result

	for (int i = 0; i < 3; i++)
	{
		g_fHeldEngOrg[entity * 3 + i] = cur[i];
		g_fHeldEngAng[entity * 3 + i] = ang[i];
	}
	g_bHeld[entity] = true;
	g_fHeldSim[entity] = GetEntDataFloat(entity, g_iOffSimTime);
	SDKCall(g_hSetAbsOrigin, entity, org);
	if (newAng[1] != ang[1])
		SDKCall(g_hSetAbsAngles, entity, newAng);
	g_iStatClientPos++;
	if (mode == CI_HOLD)
		g_iStatHold++;
	if (g_iDebug > 0)
	{
		char from[96];
		if (mode == CI_HOLD || mode == CI_OLDEST)
			FormatEx(from, sizeof(from), "%s its sample of %.3f", g_sCiMode[mode], mode == CI_HOLD ? cs.tB[0] : cs.tN);
		else
			FormatEx(from, sizeof(from), "%s its samples of %.3f and %.3f (%.2f)", g_sCiMode[mode], cs.tB[0], cs.tN, frac);
		Dbg(entity, "[posesync] ent %d position: your client draws it at %.3f %s%s: moved %.2f units from the engine's linear interpolation (yaw %.1f -> %.1f)",
			entity, drawT, from, cs.tracked ? ", from the snapshots you were sent" : "", dist, ang[1], newAng[1]);
	}
	return true;
}

// ---------------------------------------------------------------------------
// Players: move blend and the Hunter's pounce blend from the client's velocity estimate
//
// CTerrorPlayerAnimState (client.dll 0x10281e50, the same code as the server's
// ComputePoseParam_MoveYaw), outside ACT_TERROR_JOCKEY_RIDE:
//   speed = |velocity xy|; if speed > 0.5 and GetCurrentMaxGroundSpeed() > 0:
//     f = clamp(speed / ground speed, 0.01, 1), a = AngleNormalize(current feet yaw - velocity yaw)
//     move_x = cos(a) * f, move_y = sin(a) * f;   otherwise both 0
// and in ACT_TERROR_HUNTER_POUNCE, _POUNCE_IDLE and ACT_TERROR_IDLE_FALL_FROM_CHARGERHIT (0x10282711):
//   h = clamp(speed, 10, 600), T = 750 - (h - 10) * 400 / 590
//   vert_vel = 1 - (velocity z + T) / 2T, horiz_vel = h * 0.002
// The velocity is GetOuterAbsVelocity = EstimateAbsVelocity on the client and the true velocity on
// the server. The ground speed (per class and stance) is the same on both; it is taken from the
// server's own move blend and velocity in the records.
// ---------------------------------------------------------------------------

float g_fPlGroundSpeed[MAXPLAYERS + 1];

float PoseRaw(PoseModel pm, int i, float norm)
{
	return pm.start[i] + norm * (pm.end[i] - pm.start[i]);
}

// The ground speed the server's animstate divided by, from records at or before t.
float PlayerGroundSpeed(int entity, float t, PoseModel pm)
{
	ArrayList h = g_hHistory[entity];
	int n;
	int idx = FindRecIndex(entity, t, n);
	if (idx == -1 || pm.idxMoveX == -1 || pm.idxMoveY == -1)
		return g_fPlGroundSpeed[entity];
	int size = g_iRingSize, count = g_iCount[entity];
	float fallback = 0.0;
	for (int k = 0; k < 32 && n + k < count; k++)
	{
		float vx = view_as<float>(h.Get(idx, REC_VEL)), vy = view_as<float>(h.Get(idx, REC_VEL + 1));
		float speed = SquareRoot(vx * vx + vy * vy);
		float mx = PoseRaw(pm, pm.idxMoveX, view_as<float>(h.Get(idx, REC_POSE + pm.idxMoveX)));
		float my = PoseRaw(pm, pm.idxMoveY, view_as<float>(h.Get(idx, REC_POSE + pm.idxMoveY)));
		float f = SquareRoot(mx * mx + my * my);
		if (speed > 0.5 && f > 0.0105 && f < 0.995)
		{
			g_fPlGroundSpeed[entity] = speed / f;
			return speed / f;
		}
		if (fallback == 0.0 && speed > 0.5 && f >= 0.995)
			fallback = speed;       // at full blend: the ground speed is at most the speed
		idx = (idx - 1 + size) % size;
	}
	if (fallback > 0.0 && (g_fPlGroundSpeed[entity] <= 0.0 || g_fPlGroundSpeed[entity] > fallback))
		return fallback;
	return g_fPlGroundSpeed[entity];
}

bool ApplyClientMoveBlend(int entity, float drawT, float poses[MAXPOSE], float feetYaw)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return false;
	int seq = g_bClockMain[entity] ? g_iClockSeq[entity] : GetEntData(entity, g_iOffSequence);
	bool move = pm.idxMoveX != -1 && pm.idxMoveY != -1 && !(SeqKind(pm, seq) & SK_JOCKEYRIDE);
	bool pounce = pm.idxVert != -1 && pm.idxHoriz != -1 && (SeqKind(pm, seq) & SK_VEL);
	if (!move && !pounce)
		return false;
	float vel[3];
	int mode;
	if (!ClientVelocity(entity, drawT, vel, mode))
		return false;
	float speed = SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]);
	bool wrote = false;

	if (move)
	{
		bool noGs = (SeqKind(pm, seq) & SK_NOGS) != 0;    // the client's max ground speed is 0: blend 0
		float gs = noGs ? 0.0 : PlayerGroundSpeed(entity, drawT, pm);
		float mx = 0.0, my = 0.0;
		bool known = true;
		if (speed > 0.5 && !noGs)
		{
			if (gs > 0.0)
			{
				float f = speed / gs;
				if (f > 1.0) f = 1.0;
				else if (f < 0.01) f = 0.01;
				float velYaw = RadToDeg(ArcTangent2(vel[1], vel[0]));
				float a = DegToRad(AngleNorm(feetYaw - velYaw));
				mx = Cosine(a) * f;
				my = Sine(a) * f;
			}
			else
				known = false;
		}
		if (known)
		{
			float sx = PoseRaw(pm, pm.idxMoveX, poses[pm.idxMoveX]), sy = PoseRaw(pm, pm.idxMoveY, poses[pm.idxMoveY]);
			poses[pm.idxMoveX] = PoseValueFromDegrees(pm, pm.idxMoveX, mx);
			poses[pm.idxMoveY] = PoseValueFromDegrees(pm, pm.idxMoveY, my);
			wrote = true;
			g_iStatMoveBlend++;
			if (g_iDebug > 0)
				Dbg(entity, "[posesync] ent %d move blend: your client's speed estimate %.0f u/s (%s its samples), ground speed %.0f: move_x %.2f, move_y %.2f (server %.2f, %.2f)",
					entity, speed, g_sCiMode[mode], gs, mx, my, sx, sy);
		}
	}
	if (pounce)
	{
		float hs = speed;
		if (hs > 600.0) hs = 600.0;
		else if (hs < 10.0) hs = 10.0;
		float T = 750.0 - (hs - 10.0) * 400.0 * 0.00169492;
		float x2 = (T == -T) ? ((vel[2] >= T) ? 1.0 : 0.0) : (vel[2] + T) / (2.0 * T);
		float sv = PoseRaw(pm, pm.idxVert, poses[pm.idxVert]), sh = PoseRaw(pm, pm.idxHoriz, poses[pm.idxHoriz]);
		poses[pm.idxVert] = PoseValueFromDegrees(pm, pm.idxVert, 1.0 - x2);
		poses[pm.idxHoriz] = PoseValueFromDegrees(pm, pm.idxHoriz, hs * 0.002);
		wrote = true;
		if (g_iDebug > 0)
			Dbg(entity, "[posesync] ent %d pounce blend from your client's velocity estimate (%.0f u/s across, %.0f u/s up): vert_vel %.2f, horiz_vel %.2f (server %.2f, %.2f)",
				entity, speed, vel[2], PoseRaw(pm, pm.idxVert, poses[pm.idxVert]), PoseRaw(pm, pm.idxHoriz, poses[pm.idxHoriz]), sv, sh);
	}
	return wrote;
}

// ---------------------------------------------------------------------------
// Common infected: move blend the way C_Infected sets it (client.dll 0x10313c60)
//
//   v = EstimateAbsVelocity, x = v . forward, y = -(v . right)
//   fewer than 20 C_Infected on the client: CBaseAnimating 9-way blend (0x10031190): (x, y) scaled to
//     the unit square, then move_x / move_y rescaled by v / the sequence's blended linear velocity,
//     repeated up to 6 times while a value is inside (-1, 1) and its velocity is more than 1 u/s off
//     (once only for commons more than 512 units from the camera)
//   20 or more: move_x = x / g, move_y = y / g, g = the sequence's ground speed at move_x 1, move_y 0
//     (worked out at each new sequence), or z_speed without one
// The server sets move_x = v . forward / run speed, move_y = v . right / run speed from its true
// velocity on each NextBot update.
// ---------------------------------------------------------------------------

int ClientInfectedCount(int client)
{
	int tick = GetGameTickCount();
	if (g_iInfCountTick[client] == tick)
		return g_iInfCount[client];
	int n = 0;
	for (int e = MaxClients + 1; e < MAX_ENTS && client < PTX_MAX; e++)
		if (g_bTxInf[e] && g_fTxLast[client][e] > -500.0)
			n++;
	g_iInfCountTick[client] = tick;
	g_iInfCount[client] = n;
	return n;
}

// Studio_LocalPoseParameter for blend parameter p of a movement block. Returns the setting, n = cell.
float SeqLocalPose(PoseModel pm, const float blk[SM_SIZE], int p, const float poses[MAXPOSE], int &n)
{
	n = 0;
	int ip = RoundToZero(blk[SM_P0 + p]);
	int g = RoundToZero(blk[SM_G0 + p]);
	if (ip < 0 || ip >= pm.numPose || g < 2)
		return 0.0;
	float st = pm.start[ip], en = pm.end[ip];
	if (en == st)
		return 0.0;
	float v = poses[ip];
	if (pm.loop[ip] != 0.0)
	{
		float wrap = (st + en) * 0.5 + pm.loop[ip] * 0.5;
		float shift = pm.loop[ip] - wrap;
		v = v - pm.loop[ip] * float(RoundToFloor((v + shift) / pm.loop[ip]));
	}
	float s;
	if (blk[SM_KEYS] == 0.0)
	{
		float ls = (blk[SM_PS0 + p] - st) / (en - st), le = (blk[SM_PE0 + p] - st) / (en - st);
		s = (le != ls) ? (v - ls) / (le - ls) : 0.0;
		if (s < 0.0) s = 0.0;
		if (s > 1.0) s = 1.0;
		if (g > 2)
		{
			n = RoundToFloor(s * float(g - 1));
			if (n >= g - 1) n = g - 2;
			s = s * float(g - 1) - float(n);
		}
		return s;
	}
	float val = v * (en - st) + st;
	int kb = (p == 0) ? SM_KEY0 : SM_KEY1;
	for (;;)
	{
		float k0 = blk[kb + n], k1 = blk[kb + n + 1];
		s = (k1 != k0) ? (val - k0) / (k1 - k0) : 0.0;
		if (n < g - 2 && s > 1.0)
		{
			n++;
			continue;
		}
		break;
	}
	if (s < 0.0) s = 0.0;
	if (s > 1.0) s = 1.0;
	return s;
}

// Linear motion over one cycle of a sequence at these pose parameters (Studio_SeqMovement 0..1);
// returns its cycles per second (Studio_CPS), 0 without a movement block.
float SeqMotion(PoseModel pm, int seq, const float poses[MAXPOSE], float motion[3])
{
	motion[0] = 0.0; motion[1] = 0.0; motion[2] = 0.0;
	if (pm.seqMoveIdx == null || seq < 0 || seq >= pm.seqMoveIdx.Length)
		return 0.0;
	int row = pm.seqMoveIdx.Get(seq);
	if (row < 0)
		return 0.0;
	float blk[SM_SIZE];
	pm.seqMove.GetArray(row, blk);
	int n0, n1;
	float s0 = SeqLocalPose(pm, blk, 0, poses, n0);
	float s1 = SeqLocalPose(pm, blk, 1, poses, n1);
	int g0 = RoundToZero(blk[SM_G0]), g1 = RoundToZero(blk[SM_G1]);
	float cps = 0.0;
	for (int c = 0; c < 4; c++)
	{
		int x = n0 + (c & 1), y = n1 + (c >> 1);
		float w = ((c & 1) ? s0 : 1.0 - s0) * ((c >> 1) ? s1 : 1.0 - s1);
		if (w == 0.0)
			continue;
		if (x > g0 - 1) x = g0 - 1;
		if (y > g1 - 1) y = g1 - 1;
		int a = SM_ANIM + (y * g0 + x) * SM_ASTRIDE;
		cps += blk[a] * w;
		motion[0] += blk[a + 1] * w;
		motion[1] += blk[a + 2] * w;
		motion[2] += blk[a + 3] * w;
	}
	return cps;
}

void SetPoseLocal(PoseModel pm, float poses[MAXPOSE], int i, float v)
{
	if (i >= 0 && i < MAXPOSE)
		poses[i] = PoseValueFromDegrees(pm, i, v);
}

// CBaseAnimating 9-way blend (client.dll 0x10031190) with x scale 1 and y scale -1.
void Client9Way(PoseModel pm, int seq, float poses[MAXPOSE], int ix, int iy, float vx, float vy, bool iterate)
{
	float px = 0.0, py = 0.0;
	if (vx != 0.0 && FloatAbs(vx) > FloatAbs(vy))
	{
		px = (vx < 0.0) ? -1.0 : 1.0;
		py = -vy / FloatAbs(vx);
	}
	else if (vy != 0.0)
	{
		px = vx / FloatAbs(vy);
		py = (vy < 0.0) ? 1.0 : -1.0;
	}
	SetPoseLocal(pm, poses, ix, px);
	SetPoseLocal(pm, poses, iy, py);
	if (px == 0.0 && py == 0.0)
		return;
	for (int k = 0; ; k++)
	{
		float m[3];
		float cps = SeqMotion(pm, seq, poses, m);
		float sx = m[0] * cps, sy = m[1] * cps;     // GetBlendedLinearVelocity: motion / duration
		px = (FloatAbs(sx) > 0.001) ? vx / sx * px : 0.0;
		SetPoseLocal(pm, poses, ix, px);
		py = (FloatAbs(sy) > 0.001) ? vy / sy * py : 0.0;
		SetPoseLocal(pm, poses, iy, py);
		if (!iterate || k >= 5)
			break;
		bool again = (px < 1.0 && px > -1.0 && (vx - sx < -1.0 || vx - sx > 1.0))
			|| (py < 1.0 && py > -1.0 && (vy - sy < -1.0 || vy - sy > 1.0));
		if (!again)
			break;
	}
}

bool ApplyCommonMove(int entity, float drawT)
{
	PoseModel pm;
	if (!GetPoseModel(entity, pm))
		return false;
	int ix = pm.idxMoveX, iy = pm.idxMoveY;
	if (ix == -1 && iy == -1)
		return false;
	float vel[3];
	int mode;
	if (!ClientVelocity(entity, drawT, vel, mode))
		return false;
	float ang[3], fwd[3], right[3], up[3];
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
	GetAngleVectors(ang, fwd, right, up);
	float lx = GetVectorDotProduct(vel, fwd), ly = -GetVectorDotProduct(vel, right);
	int seq = GetEntData(entity, g_iOffSequence);

	float poses[MAXPOSE];
	for (int i = 0; i < MAXPOSE; i++)
		poses[i] = GetEntDataFloat(entity, g_iOffPose + i * 4);
	float sx = (ix != -1) ? PoseRaw(pm, ix, poses[ix]) : 0.0, sy = (iy != -1) ? PoseRaw(pm, iy, poses[iy]) : 0.0;

	int count = ClientInfectedCount(g_iShooter);
	char how[96];
	if (ix != -1 && iy != -1 && count < 20)
	{
		float org[3], eye[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", org);
		GetClientEyePosition(g_iShooter, eye);
		bool nearCam = GetVectorDistance(org, eye, true) < 262144.0;
		Client9Way(pm, seq, poses, ix, iy, lx, ly, nearCam);
		FormatEx(how, sizeof(how), "9-way blend%s (%d commons on your client)", nearCam ? ", refined" : " (over 512 units: one pass)", count);
	}
	else
	{
		float gs = 0.0;
		if (ix != -1 && iy != -1)
		{
			float p2[MAXPOSE];
			p2 = poses;
			SetPoseLocal(pm, p2, ix, 1.0);
			SetPoseLocal(pm, p2, iy, 0.0);
			float m[3];
			float cps = SeqMotion(pm, seq, p2, m);
			gs = (cps > 0.0) ? GetVectorLength(m) * cps : 0.0;
		}
		if (gs > 0.0)
		{
			SetPoseLocal(pm, poses, ix, lx / gs);
			SetPoseLocal(pm, poses, iy, ly / gs);
			FormatEx(how, sizeof(how), "velocity / ground speed %.0f (%d commons on your client)", gs, count);
		}
		else
		{
			float zs = (g_cvZSpeed != null) ? g_cvZSpeed.FloatValue : 250.0;
			if (zs == 0.0)
				return false;
			SetPoseLocal(pm, poses, ix, lx / zs);
			SetPoseLocal(pm, poses, iy, ly / zs);
			FormatEx(how, sizeof(how), "velocity / z_speed %.0f (%d commons on your client)", zs, count);
		}
	}
	if (ix != -1)
		SetEntDataFloat(entity, g_iOffPose + ix * 4, poses[ix], false);
	if (iy != -1)
		SetEntDataFloat(entity, g_iOffPose + iy * 4, poses[iy], false);
	g_iStatCommonMove++;
	if (g_iDebug > 0)
		Dbg(entity, "[posesync] ent %d (common) move blend: your client's speed estimate %.0f u/s (%s its samples; forward %.0f, left %.0f), %s: move_x %.2f, move_y %.2f (server %.2f, %.2f)",
			entity, SquareRoot(vel[0] * vel[0] + vel[1] * vel[1]), g_sCiMode[mode], lx, ly, how,
			ix != -1 ? PoseRaw(pm, ix, poses[ix]) : 0.0, iy != -1 ? PoseRaw(pm, iy, poses[iy]) : 0.0, sx, sy);
	return true;
}

// ---------------------------------------------------------------------------
// Model: per-sequence movement (for the common move blend)
// ---------------------------------------------------------------------------

float ReadFloatAt(File f, int pos)
{
	return view_as<float>(ReadIntAt(f, pos));
}

// Studio_AnimPosition at cycle 1: where the animation's movement blocks have moved it by its end.
bool AnimMotion(File f, int ad, float out[3])
{
	out[0] = 0.0; out[1] = 0.0; out[2] = 0.0;
	int nf = ReadIntAt(f, ad + 16), nm = ReadIntAt(f, ad + 20), mi = ReadIntAt(f, ad + 24);
	if (nm <= 0 || nm > 64)
		return false;
	float frame = float(nf - 1), prev = 0.0;
	for (int k = 0; k < nm; k++)
	{
		int mb = ad + mi + k * 44;      // mstudiomovement_t: endframe, flags, v0, v1, angle, vector[3], position[3]
		float end = float(ReadIntAt(f, mb));
		if (end >= frame)
		{
			float fr = (end != prev) ? (frame - prev) / (end - prev) : 0.0;
			float v0 = ReadFloatAt(f, mb + 8), v1 = ReadFloatAt(f, mb + 12);
			float d = v0 * fr + 0.5 * (v1 - v0) * fr * fr;
			for (int j = 0; j < 3; j++)
				out[j] += d * ReadFloatAt(f, mb + 20 + j * 4);
			return true;
		}
		prev = end;
		for (int j = 0; j < 3; j++)
			out[j] = ReadFloatAt(f, mb + 32 + j * 4);
	}
	// no block reaches the last frame: Studio_AnimPosition (0x10342a10) keeps the position at the end
	// of the last block, and Studio_SeqMovement uses it as the animation's motion
	return true;
}

// Reads the movement block of each sequence this file added (fileSeqs: global index, seqdesc offset).
void ReadSequenceMovement(File f, PoseModel pm, StringMap seen, ArrayList fileSeqs)
{
	if (pm.seqMove == null || fileSeqs.Length == 0)
		return;
	int numAnim = ReadIntAt(f, 180), animBase = ReadIntAt(f, 184);
	int numPose = ReadIntAt(f, HDR_NUMPOSEPARAMS), poseIndex = ReadIntAt(f, HDR_POSEPARAMINDEX);
	char name[POSE_NAME_LEN];
	for (int k = 0; k < fileSeqs.Length; k++)
	{
		int pair[2];
		fileSeqs.GetArray(k, pair);
		int sb = pair[1];
		int g0 = ReadIntAt(f, sb + 68), g1 = ReadIntAt(f, sb + 72);
		if (g0 < 1 || g1 < 1 || g0 * g1 > SM_MAXANIMS)
			continue;
		float blk[SM_SIZE];
		bool anyMotion = false;
		int animList = sb + ReadIntAt(f, sb + 60);
		for (int slot = 0; slot < g0 * g1; slot++)
		{
			int ai = ReadShortAt(f, animList + slot * 2);
			int a = SM_ANIM + slot * SM_ASTRIDE;
			if (ai < 0 || ai >= numAnim)
				continue;
			int ad = animBase + ai * 100;
			int nf = ReadIntAt(f, ad + 16);
			blk[a] = (nf > 1) ? ReadFloatAt(f, ad + 8) / float(nf - 1) : 0.0;
			float m[3];
			if (AnimMotion(f, ad, m))
			{
				blk[a + 1] = m[0]; blk[a + 2] = m[1]; blk[a + 3] = m[2];
				anyMotion = true;
			}
		}
		if (!anyMotion)
			continue;
		blk[SM_G0] = float(g0);
		blk[SM_G1] = float(g1);
		for (int p = 0; p < 2; p++)
		{
			int local = ReadIntAt(f, sb + 76 + p * 4);
			int merged = -1;
			if (local >= 0 && local < numPose)
			{
				int b = poseIndex + local * POSEDESC_SIZE;
				ReadStringAt(f, b + ReadIntAt(f, b), name, sizeof(name));
				StringToLower(name);
				if (!seen.GetValue(name, merged))
					merged = -1;
			}
			blk[SM_P0 + p] = float(merged);
			blk[SM_PS0 + p] = ReadFloatAt(f, sb + 84 + p * 4);
			blk[SM_PE0 + p] = ReadFloatAt(f, sb + 92 + p * 4);
		}
		int pki = ReadIntAt(f, sb + 160);
		blk[SM_KEYS] = (pki != 0) ? 1.0 : 0.0;
		if (pki != 0)
		{
			for (int i = 0; i < g0 && i < SM_MAXKEYS; i++)
				blk[SM_KEY0 + i] = ReadFloatAt(f, sb + pki + i * 4);
			for (int i = 0; i < g1 && i < SM_MAXKEYS; i++)
				blk[SM_KEY1 + i] = ReadFloatAt(f, sb + pki + (g0 + i) * 4);
		}
		int row = pm.seqMove.PushArray(blk);
		pm.seqMoveIdx.Set(pair[0], row);
	}
}

// ---------------------------------------------------------------------------
// Run-up of a player's movement sequence on the shooter's client
// ---------------------------------------------------------------------------

// How many cycles of a player's movement sequence the shooter's client has not played, by its
// clock drawT, because it restarted the sequence later than the server. The client restarts the
// main sequence at cycle 0 when the new m_mainSequenceStartTime reaches it (0x1027e760 ->
// 0x10145f10), on its own clock; until the snapshot that brought the change, it has not started it.
// Worked out once per run (from the run's first records and the snapshots the shooter was sent) and
// kept for the rest of the run.
// The client also plays the run at the cycle rate of its own move blend, set from its speed
// estimate (0x10281e50), which trails the true speed while the player speeds up. That is not added:
// counting it put the start of a run behind the client in game, while runs older than the history
// (where it could not be counted) matched.
float ClientRunLag(int entity, PoseModel pm, int seq, const int a[REC_SIZE], float drawT, float &restartDelay)
{
	restartDelay = 0.0;
	if (SeqKind(pm, seq) & SK_JOCKEYRIDE)
		return 0.0;
	int sh = g_iShooter;
	if (sh <= 0 || sh >= PTX_MAX || entity >= PTX_MAX)
		return 0.0;
	int mainStart = a[REC_SEQSTART];
	if (g_iRlSeq[sh][entity] == seq && g_iRlStartBits[sh][entity] == mainStart)
	{
		restartDelay = g_fRlDelay[sh][entity];
		return g_fRlLag[sh][entity];
	}

	ArrayList h = g_hHistory[entity];
	int n;
	int idx = FindRecIndex(entity, drawT, n);
	if (idx == -1)
		return 0.0;
	int size = g_iRingSize, count = g_iCount[entity];
	int parity = a[REC_PARITY];
	// first record of this run: the same sequence, parity and m_mainSequenceStartTime
	int first = -1;
	int k = n;
	for (int j = idx; k < count; k++)
	{
		if (h.Get(j, REC_SEQ) != seq || h.Get(j, REC_PARITY) != parity || h.Get(j, REC_SEQSTART) != mainStart)
			break;
		first = j;
		j = (j - 1 + size) % size;
	}
	if (first == -1)
		return 0.0;
	// the run started before the history: its restart can no longer be worked out, take none and
	// keep that for the run
	bool complete = (k < count);

	float lag = 0.0;
	if (complete && g_iPlTxCount[sh][entity] > 0)
	{
		float runStart = view_as<float>(h.Get(first, REC_SIM));
		int startTick = h.Get(first, REC_TICK);
		int ti = g_iPlTxHead[sh][entity], found = -1;
		for (int c = 0; c < g_iPlTxCount[sh][entity]; c++)
		{
			int tk = g_iPlTx[sh][entity * PTX_RING + ti];
			if (tk < startTick)
				break;
			found = tk;
			ti = (ti - 1 + PTX_RING) % PTX_RING;
		}
		// in ticks from the run's first record: the transmit hook and the lag compensation record can
		// read the tick count at different points of the same server frame, so the smallest gap seen
		// between them (g_iTxRecGap) is taken as "the same tick"
		if (found >= 0 && found - startTick - g_iTxRecGap > 0)
		{
			float clientStart = runStart + float(found - startTick - g_iTxRecGap) * g_fTick;
			restartDelay = clientStart - runStart;
			// the server's cycles from its start to the client's restart, from the run's own records
			bool loops = SeqLoops(pm, seq);
			int p[REC_SIZE], q[REC_SIZE];
			int j = first, head = g_iHead[entity];
			h.GetArray(j, p);
			while (j != head)
			{
				int jn = (j + 1) % size;
				h.GetArray(jn, q);
				float t0 = view_as<float>(p[REC_SIM]), t1 = view_as<float>(q[REC_SIM]);
				if (t0 >= clientStart || q[REC_SEQ] != seq || q[REC_PARITY] != parity)
					break;
				if (t1 > clientStart) t1 = clientStart;
				float rs = CycleRate(p, q, loops);
				if (rs > 0.0)
					lag += rs * (t1 - t0);
				p = q;
				j = jn;
			}
		}
	}
	g_iRlSeq[sh][entity] = seq;
	g_iRlStartBits[sh][entity] = mainStart;
	g_fRlLag[sh][entity] = lag;
	g_fRlDelay[sh][entity] = restartDelay;
	return lag;
}
