//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//You should have received a copy of the GNU General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <dhooks>
#include <gvazdas_random>

#undef _NATIVE_ONLY
#include <l4d_path_to_goal>

#define PLUGIN_VERSION 			"1.85 2026-10-18"

public Plugin myinfo =
{
	name = "[L4D1/L4D2] Path To Goal",
	author = "gvazdas, zyiks",
	description = "Automatic path to goal indicator for Survivor team.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=352685, https://codeberg.org/gvazdas/l4d2_zombie_master"
}

// Called before OnPluginStart, in case the plugin wants to check for load failure. 
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    switch (GetEngineVersion())
    {
        case Engine_Left4Dead2: g_bL4D2 = true; // FUTURE: Engine_Left4Dead2OB
        case Engine_Left4Dead:  g_bL4D2 = false;
        default:
        {
            strcopy(error,err_max,"Plugin only supports L4D1 and L4D2.");
		    return APLRes_Failure;
        }
    }
    MarkNativeAsOptional("L4D_NavArea_GetZ");
    MarkNativeAsOptional("L4D_NavArea_GetElevator");
    MarkNativeAsOptional("L4D_NavArea_IsBlocked");
    MarkNativeAsOptional("L4D_NavArea_GetCorner");
    MarkNativeAsOptional("L4D_NavArea_GetLadder");
    RegPluginLibrary("l4d_path_to_goal");
    CreateNative("L4D_Path_To_Goal", Native_RequestGuide);
	return APLRes_Success;
}

bool g_bLate = true; // Plugin just started, might be in the middle of a map.

// Called once in the entire lifetime of the plugin.
public void OnPluginStart()
{
    LoadTranslations("l4d_path_to_goal.phrases");
    LoadTranslations("common.phrases");
    LoadSDK();

    RegConsoleCmd("path_to_goal",       CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("pathtogoal",         CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("wheretogo",          CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("imlost",             CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("guide",              CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("ptg",                CmdRequestGuide, "Point where to go to progress in the map.");
    RegConsoleCmd("ptg_menu",           CmdMenu,         "Open Path To Goal menu.");
    
    RegAdminCmd("l4d_path_to_goal_recalculate", CmdRecalculate, ADMFLAG_ROOT,"Recalculate guide points.");
    RegAdminCmd("l4d_path_to_goal_print",       CmdPrint, ADMFLAG_ROOT,"Print g_GuideCells.");
    if (g_bL4D2) RegAdminCmd("l4d_path_to_goal_rescue", CmdRescue, ADMFLAG_ROOT,"Send in rescue vehicle.");
    RegAdminCmd("l4d_path_to_goal_ground", CmdGround, ADMFLAG_ROOT,"Check if origin is near ground.");
    #if DEBUG
    RegAdminCmd("l4d_path_to_goal_validate", CmdValidate, ADMFLAG_ROOT,"Print validation results for cell index if provided, or closest cell to player.");
    #endif
    RegAdminCmd("l4d_path_to_goal_recomputeflow", CmdRecomputeFlow, ADMFLAG_ROOT,"Force TerrorNavMesh::RecomputeFlowDistances to fire.");

    g_hCvarEnable = CreateConVar("l4d_path_to_goal_enable", "1",
    "0=OFF, 1=ON.",FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarEnable.AddChangeHook(ConVarChanged_Cvars);
  	
    g_hCvarMax = CreateConVar("l4d_path_to_goal_max", "32",
    "Max beams per request. Increasing this can potentially cause crashes for clients.",FCVAR_NOTIFY, true, 1.0, true, 1000.0);

    g_hCvarSurvivors = CreateConVar("l4d_path_to_goal_survivor", "1",
    "Allow survivors to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarInfected = CreateConVar("l4d_path_to_goal_infected", "1",
    "Allow infected to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarSpec = CreateConVar("l4d_path_to_goal_spec", "1",
    "Allow observers/spectators to request.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarAlive = CreateConVar("l4d_path_to_goal_alive", "0",
    "Allow request based on alive state: 0=all,1=alive only,2=dead only.",FCVAR_NOTIFY, true, 0.0, true, 2.0);

    g_hCvarBudget = CreateConVar("l4d_path_to_goal_budget", "0.5",
    "Max CPU budget (ms per frame) for escape route calculation. Larger budget makes requests available faster at the expense of server lag. 0 for infinite budget.",FCVAR_NOTIFY, true, 0.0, true, 1000.0);

    g_hCvarDetourBudget = CreateConVar("l4d_path_to_goal_detour_budget", "10.0",
    "Max CPU budget (ms) for detour beams. 0 for infinite budget.",FCVAR_NOTIFY, true, 0.0, true, 100.0);

    g_hCvarFinale = CreateConVar("l4d_path_to_goal_finale", "1",
    "On Finale maps, connect to rescue vehicle... 0: ALWAYS, 1: FINALE STARTED, 2: RESCUE ARRIVED, 3: NEVER",FCVAR_NOTIFY, true, 0.0, true, 3.0);
    g_hCvarFinale.AddChangeHook(ConVarFinaleSetting);

    g_hCvarFinaleAuto = CreateConVar("l4d_path_to_goal_finale_auto", "0",
    "Automatically draw beams to rescue vehicle for all clients. l4d_path_to_goal_finale must be less than 3.",FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hCvarCooldown = CreateConVar("l4d_path_to_goal_cooldown", "2.0",
    "Cooldown in seconds between ptg calls. 0 to disable. Zombie Master ignores these.",FCVAR_NOTIFY, true, 0.0, true, 10000.0);

  	g_hCvarMPGameMode = FindConVar("mp_gamemode");
  	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);

    HookEvent("round_start_post_nav",     evtPostNav,            EventHookMode_PostNoCopy);
    HookEvent("nav_blocked",              evtNavBlocked,         EventHookMode_Post);
    HookEvent("nav_generate",             evtNavGenerate,        EventHookMode_PostNoCopy);
	HookEvent("finale_start", 			  evtFinaleStart,        EventHookMode_PostNoCopy);
	HookEvent("finale_radio_start", 	  evtFinaleStart,        EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_ready", 	  evtFinaleVehicle,      EventHookMode_PostNoCopy);
    HookEntityOutput("trigger_finale",    "FinaleEscapeStarted", OnFinaleEscapeStarted);
    if (g_bL4D2)
    {
        HookEvent("gauntlet_finale_start", 	  evtGauntletStart,  EventHookMode_PostNoCopy);
        HookEvent("finale_vehicle_incoming",  evtFinaleVehicle,  EventHookMode_PostNoCopy);
    }

    AutoExecConfig(true, CONFIG_FILENAME); // this is queued, will run later

    int i = 1;
    while (i<=MaxClients)
    {
        if (IsValidClient(i)) ResetClientSettings(i);
        i += 1;
    }

    g_bLate = true; // Plugin JUST started, we might be in the middle of a map.
}

// Called by every plugin after they have all started.
public void OnAllPluginsLoaded()
{
    elevator_available = GetFeatureStatus(FeatureType_Native,"L4D_NavArea_GetElevator")==FeatureStatus_Available; // introduced elevator, ladder and getZ at the same time.
    blocked_available = GetFeatureStatus(FeatureType_Native,"L4D_NavArea_IsBlocked")==FeatureStatus_Available;
    if (!elevator_available || !blocked_available) LogMessage("Please update l4dhooks for better performance.");
    g_hCvarZM = FindConVar("zm_enable"); // check if zombie master is active
    if (!g_bLate) return;
    Check_Guidable();
    g_bLate = false;
    if (L4D_HasMapStarted())
    {
        map_started = true;
        nav_started = true;
        finale = L4D_IsFinaleActive(); // Check if Finale is active
        if (finale)
        {
            // ignore "fake" VScript finales
            int entity = FindEntityByClassname(-1, "trigger_finale");
            finale = entity>0 && IsValidEntity(entity);
        }

        // Figure out if rescue vehicle has arrived, we're in gauntlet, etc.
        if (finale)
        {
            if (g_bL4D2)
            {
                switch (L4D2_GetCurrentFinaleStage())
                {
                    case FINALE_GAUNTLET_1,FINALE_GAUNTLET_2,FINALE_GAUNTLET_BOSS,FINALE_GAUNTLET_BOSS_INCOMING,
                         FINALE_GAUNTLET_HORDE, FINALE_GAUNTLET_HORDE_BONUSTIME, FINALE_GAUNTLET_START:
                    {
                        finale_gauntlet = true;
                    }
                    case FINALE_GAUNTLET_ESCAPE:
                    {
                        finale_gauntlet = true;
                        finale_rescue = true;
                    }
                    case FINALE_HORDE_ESCAPE:
                    {
                        finale_rescue = true;
                    }
                }
            }
            else
            {
                finale_rescue = true; // too much work to check for hammerids, assume the vehicle is ready
            }
        }
    }
}

public void OnMapStart()
{
	Guide_Cleanup();
    g_bMapFail = false;

    // Randomize colors
    color_forward = {0,231,0,249};
    color_forward[0] = GetRandomInt(0,20);
    color_forward[1] += GetRandomInt(-10,10);
    color_forward[2] = GetRandomInt(0,20);

    color_backward = {128,0,0,128};
    color_backward[0] += GetRandomInt(-5,5);
    color_backward[1] = GetRandomInt(0,10);
    color_backward[2] = GetRandomInt(0,10);
    
    g_iLaser = PrecacheModel(VMT_LASERBEAM, true);
    g_iLaserWhite = PrecacheModel(VMT_LASERBEAM_WHITE, true);
    g_iLaserCustom = PrecacheModel(VMT_LASERBEAM_CUSTOM, true);
    g_bSound = PrecacheSound(SOUND_BEAM_ON) && PrecacheSound(SOUND_BEAM_OFF);
    PrecacheSound(SOUND_DENY);
    
    t_nav = -1.0;
    timer_nav = null;
    RequestFrame(MapStarted);
}

void MapStarted()
{
    map_started = true;
}

public void OnMapEnd()
{
    Guide_Cleanup();
    g_bMapFail = false;
    map_started = false;
    nav_started = false;
    t_nav = -1.0;
    beams_cooldown_reset(_,true); // reset all requests and cooldowns
    timer_nav = null;
    finale = false;
    finale_gauntlet = false;
    finale_rescue = false;
    g_iLaser = 0;
    g_iLaserWhite = 0;
    g_iLaserCustom = 0;
    g_bSound = false;
}

public void OnPluginEnd()
{
    Guide_Cleanup();
}

// Called when the map has loaded, servercfgfile (server.cfg) has been executed, and all plugin configs are done executing.
public void OnConfigsExecuted()
{
    GetCvars();
    #if DEBUG
    SetConVarFloat(g_hCvarDetourBudget,0.0);
    #endif
}

void OnFinaleEscapeStarted(const char[] output, int activator, int caller, float delay)
{
    FinaleVehicleReady();
}

void evtFinaleVehicle(Event event, const char[] name, bool dontBroadcast)
{
    FinaleVehicleReady();
}

stock void FinaleVehicleReady()
{
    #if DEBUG
    LogMessage("FinaleVehicleReady");
    #endif
    if (!finale) return;
    finale_rescue = true;
    if (!enable) return;
    if (g_hCvarFinale.IntValue==FINALE_NEVER) return;
    if (guide_ready && !finale_stitched && should_stitch_finale()) stitch_finale();
    if (finale_stitched && g_hCvarFinaleAuto.BoolValue) CreateTimer(2.0,Timer_Guide_All_Clients,5.0,TIMER_FLAG_NO_MAPCHANGE);
}

void evtFinaleStart(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
    LogMessage("evtFinaleStart");
    #endif
    finale = true;
    if (!enable) return;
    CreateTimer(0.1,FinalePost,_,TIMER_FLAG_NO_MAPCHANGE);
}

void evtGauntletStart(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG
    LogMessage("evtGauntletStart");
    #endif
    if (finale_stitched && !use_gauntlet_logic()) Guide_Cleanup(); // need to recalculate
    finale = true;
    finale_gauntlet = true;
    if (!enable) return;
    CreateTimer(0.1,FinalePost,_,TIMER_FLAG_NO_MAPCHANGE);
}

Action FinalePost(Handle timer)
{
    if (!enable) return Plugin_Stop;
    if (guide_ready && !finale_stitched && should_stitch_finale()) stitch_finale();
    else if (!guide_ready) Timer_CheckRequests(null);
    return Plugin_Stop;
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void evtPostNav(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG>1
        LogMessage("round_start_post_nav");
    #endif
    nav_started = true;
    finale = false;
    finale_rescue = false;
    finale_gauntlet = false;
    NavChanged();
}

void evtNavBlocked(Event event, const char[] name, bool dontBroadcast)
{
    if (!enable || !nav_started || !map_started) return;
    Address navArea = L4D_GetNavAreaByID(event.GetInt("area"));
    if (!navArea_escape(navArea)) return;
    #if DEBUG>1
    bool blocked = event.GetBool("blocked");
    LogMessage("nav_blocked escape %d blocked %d area %d", navArea_escape(navArea), blocked, navArea);
    #endif
    if (!g_bFlowRecomputeHooked || finale) NavChanged();
}

void evtNavGenerate(Event event, const char[] name, bool dontBroadcast)
{
    #if DEBUG>1
    LogMessage("nav_generate");
    #endif
    NavChanged();
}

void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RequestFrame(Check_Guidable);
}

// Finale cvar changed, may need to redraw.
void ConVarFinaleSetting(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!g_bFoundRescueVehicle || !guide_ready) return;
    Guide_Prep();
}

Action CmdRecalculate(int client, int args)
{
    if (!enable || !map_started || !nav_started || !gamemode_guidable || !nav_started)
    {
        ReplyToCommand(client, "[PTG] %t", "ptg_disabled");
        if (IsValidClient(client)) EmitSoundToClient(client,SOUND_DENY);
        return Plugin_Handled;
    }
    g_bMapFail = false; // force recalculation
    if (!PrepBusy()) Guide_Prep();
    else
    {
        if (IsValidClient(client)) EmitSoundToClient(client,SOUND_DENY);
        ReplyToCommand(client, "[PTG] %t", "ptg_busy");
    }
    return Plugin_Handled;
}

Action CmdPrint(int client, int args)
{
    if (!guide_ready || g_GuideCells==null || g_GuideCells.Length<=0) return Plugin_Handled;
    static Cell cell;
    ReplyToCommand(client, "index navArea flow pos");
    for (int i = 0; i < g_GuideCells.Length; i++)
    {
        g_GuideCells.GetArray(i,cell,sizeof(Cell));
        ReplyToCommand(client, "%d %d %.1f (%.1f %.1f %.1f)", i, cell.navArea, cell.flow, cell.center[0], cell.center[1], cell.center[2]);
    }
    return Plugin_Handled;
}

#if DEBUG
Action CmdValidate(int client, int args)
{
    if (!guide_ready || g_GuideCells == null || g_GuideCells.Length<1) return Plugin_Handled;
    int i = 0;
    if (args>0)
    {
        i = GetCmdArgInt(1);
        if (i<0) i = 0;
        else if (i>=g_GuideCells.Length) i = g_GuideCells.Length-1;
    }
    else if (IsValidClient(client))
    {
        if (!RequestGuide(client,5.0,true)) return Plugin_Handled;
        i = g_iStart;
    }

    static Cell cell, cell_before, cell_after;
    
    g_GuideCells.GetArray(i,cell,sizeof(Cell));
    ReplyToCommand(client, "%d %d %.1f (%.1f %.1f %.1f)", i, cell.navArea, cell.flow, cell.center[0], cell.center[1], cell.center[2]);
    ReplyToCommand(client, "valid ground %d", valid_ground(cell.center));
    if (IsValidClient(client))
    {
        static float pos_down[3], pos_up[3];
        pos_down = cell.center; pos_down[2] -= 1000.0;
        pos_up = cell.center; pos_up[2] += 1000.0;
        DrawBeam(client,pos_down,pos_up);
    }
    bool cell_behind = (i-1)>=0;
    bool cell_ahead = (i+1)<g_GuideCells.Length;

    if (cell_behind)
    {
        g_GuideCells.GetArray(i-1,cell_before,sizeof(Cell));
        ReplyToCommand(client, "behind LOS %d (hit %d props %d flags %d name %s)",
        twopos_traversable(cell_before.center,cell.center), g_iHitEntity, g_iHitSurfaceProps, g_iHitSurfaceFlags, g_sHitSurfaceName);
    }
    if (cell_ahead)
    {
        g_GuideCells.GetArray(i+1,cell_after,sizeof(Cell));
        ReplyToCommand(client, "ahead LOS %d (hit %d props %d flags %d name %s)",
        twopos_traversable(cell_after.center,cell.center), g_iHitEntity, g_iHitSurfaceProps, g_iHitSurfaceFlags, g_sHitSurfaceName);
    }
    if (cell_behind && cell_ahead)
    {
        ReplyToCommand(client, "ahead-behind LOS %d (hit %d props %d flags %d name %s) mid-ground %d",
        twopos_traversable(cell_after.center,cell_before.center), g_iHitEntity, g_iHitSurfaceProps, g_iHitSurfaceFlags, g_sHitSurfaceName, midpoint_valid_ground(cell_after.center,cell_before.center));
    }
    return Plugin_Handled;
}
#endif

Action CmdRescue(int client, int args)
{
    L4D2_SendInRescueVehicle();
    return Plugin_Handled;
}

Action CmdGround(int client, int args)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Stop;
    static float pos[3];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
    ReplyToCommand(client,"Ground %d",valid_ground(pos));
    return Plugin_Handled;
}

Action CmdRecomputeFlow(int client, int args)
{
    if (g_hRecomputeFlow == null) return Plugin_Handled;
    Address ptr_navmesh = L4D_GetPointer(POINTER_NAVMESH);
    if (ptr_navmesh == Address_Null) return Plugin_Handled;
    SDKCall(g_hRecomputeFlow,ptr_navmesh);
    return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return;
    beams_cooldown_reset(client,true); // reset cooldown and last request from client
    RequestFrame(ResetClientSettings,client);
    g_CellRequestsPref[client].chat = true; // set once, then monitor what they're using to call client cmds
}

// NATIVE //

void Native_RequestGuide(Handle plugin, int numParams)
{
    if (!enable || !gamemode_guidable || !nav_started || !map_started) return;
    int client = (numParams>0) ? GetNativeCell(1) : -1;
    float duration = (numParams>1) ? view_as<float>(GetNativeCell(2)) : 5.0;
    bool backward = (numParams>2) ? view_as<bool>(GetNativeCell(3)) : false;
    bool join_client = (numParams>3) ? view_as<bool>(GetNativeCell(4)) : true;
    bool hint = (numParams>4) ? view_as<bool>(GetNativeCell(5)) : true;
    RequestGuide(client,duration,backward,join_client,hint);
}

// CLIENT COMMAND // 

float tClientRequest[MAXPLAYERS+1];

Action CmdRequestGuide(int client, int args)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Handled;
    float t_now = GetGameTime();
    if (FloatAbs(tClientRequest[client]-t_now)<0.1) return Plugin_Handled; // anti-spam
    tClientRequest[client] = t_now;
    UpdateClientPreferredChannel(client,GetCmdReplySource());
    if (!enable || !map_started || !nav_started || !gamemode_guidable || g_iLaser<=0 || g_bMapFail)
    {
        ReplyToCommand(client, "[PTG] %t", "ptg_disabled");
        EmitSoundToClient(client,SOUND_DENY);
        return Plugin_Handled;
    }
    bool reset;
    if (!g_CellRequestsPref[client].menu_opened)
    {
        reset = true;
        ResetClientSettings(client);
    }
    if (args>0)
    {
        if (!reset) ResetClientSettings(client);
        static char arg[16];
        int i = 0;
        while (i<=10)
        {
            if (args>i)
            {
                GetCmdArg(i+1,arg,sizeof(arg));
                ProcessArgPref(client,arg);
            }
            else break;
            i += 1;
        }
    }
    float duration = g_CellRequestsPref[client].duration;
    bool backward = g_CellRequestsPref[client].backward;
    bool hint = g_CellRequestsPref[client].hint;
    RegisterClientPrefs(client);
    RequestGuide(client,duration,backward,true,hint);
    return Plugin_Handled;
}

// Read client intent from command arguments.
stock void ProcessArgPref(int client, char arg[16])
{
    switch (CharToLower(arg[0]))
    {
        case 'a': // arrow. beam increases in width from start to end
        {
            g_sCustomKeysPref[client][3] = 'a';
            return;
        }
        case 'b': // backward
        {
            g_CellRequestsPref[client].backward = true;
            return;
        }
        case 'c': // custom
        {
            if (g_iLaserCustom>0) g_sCustomKeysPref[client][0] = 'c';
            return;
        }
        case 'd': // delay
        {
            g_sCustomKeysPref[client][4] = 'd';
            return;
        }
        case 's': // small, shake or sound
        {
            if (strncmp(arg,"small",5,false)==0)      g_sCustomKeysPref[client][2] = 's';
            else if (strncmp(arg,"shake",5,false)==0) g_sCustomKeysPref[client][1] = 's';
            else if (strncmp(arg,"sound",5,false)==0) g_sCustomKeysPref[client][5] = 's';
            return;
        }
        case 'l': // large
        {
            g_sCustomKeysPref[client][2] = 'l';
            return;
        }
        case 'w': // wh
        {
            if (g_iLaserWhite>0) g_sCustomKeysPref[client][0] = 'w'; // VMT_LASERBEAM_WHITE
            return;
        }
    }
    float duration_new = StringToFloat(arg);
    if (0.1 <= duration_new <= 60.0) g_CellRequestsPref[client].duration = duration_new;
}

// MENU // 

Menu menu_ptg;

Action CmdMenu(int client, int args)
{
    if (!IsValidClient(client) || IsFakeClient(client)) return Plugin_Handled;
    UpdateClientPreferredChannel(client,GetCmdReplySource());
    if (!enable || !map_started || !nav_started || !gamemode_guidable || g_iLaser<=0 || g_bMapFail)
    {
        ReplyToCommand(client, "[PTG] %t", "ptg_disabled");
        EmitSoundToClient(client,SOUND_DENY);
        return Plugin_Handled;
    }
    g_CellRequestsPref[client].menu_opened = true;
    if (menu_ptg==null) create_menu();
    menu_ptg.Display(client,MENU_TIME_FOREVER);
    return Plugin_Handled;
}

void create_menu()
{		
	#if DEBUG
        LogMessage("create_menu");
    #endif
	delete menu_ptg;
    menu_ptg = new Menu(main_menu_Handler, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
    SetMenuOptionFlags(menu_ptg,MENUFLAG_NO_SOUND);
    menu_ptg.ExitButton = true;
    menu_ptg.SetTitle("l4d_path_to_goal");
    menu_ptg.AddItem("a", "!ptg");
    menu_ptg.AddItem("b", "Duration: ");
    menu_ptg.AddItem("c", "Backward");
    menu_ptg.AddItem("d", "Style: ");
    menu_ptg.AddItem("e", "Delay");
    menu_ptg.AddItem("f", "Sound");
    menu_ptg.AddItem("g", "Size: ");
    menu_ptg.AddItem("h", "Arrow");
    menu_ptg.AddItem("i", "Shake");
    menu_ptg.AddItem("j", "Hint");
    menu_ptg.AddItem("k", "Reset");
}

int main_menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    if (!IsValidClient(param1)) return 0;
    switch(action) 
    {
        case MenuAction_DisplayItem:
        {
            static char info[2];
            menu.GetItem(param2, info, sizeof(info));
            static char display[64];
            switch (info[0])
            {
                case 'b':
                {
                    Format(display, sizeof(display), "Duration: %.1f s", g_CellRequestsPref[param1].duration); 
                    return RedrawMenuItem(display);
                }
                case 'c':
                {
                    Format(display, sizeof(display), "Backward %T", g_CellRequestsPref[param1].backward ? "On" : "Off", param1);
                    return RedrawMenuItem(display);
                }
                case 'd':
                {
                    switch (g_sCustomKeysPref[param1][0])
                    {
                        case 'c': display = "Custom";
                        case 'w': display = "Wallhack";
                        default: display = "-";
                    }
                    Format(display, sizeof(display), "Style: %s", display);
                    return RedrawMenuItem(display);
                }
                case 'e':
                {
                    Format(display, sizeof(display), "Delay %T", g_sCustomKeysPref[param1][4]==0 ? "Off" : "On", param1);
                    return RedrawMenuItem(display);
                }
                case 'f':
                {
                    Format(display, sizeof(display), "Sound %T", g_sCustomKeysPref[param1][5]==0 ? "Off" : "On", param1);
                    return RedrawMenuItem(display);
                }
                case 'g':
                {
                    switch (g_sCustomKeysPref[param1][2])
                    {
                        case 's': display = "Small";
                        case 'l': display = "Large";
                        default: display = "-";
                    }
                    Format(display, sizeof(display), "Size: %s", display);
                    return RedrawMenuItem(display);
                }
                case 'h':
                {
                    Format(display, sizeof(display), "Arrow %T", g_sCustomKeysPref[param1][3]==0 ? "Off" : "On", param1);
                    return RedrawMenuItem(display);
                }
                case 'i':
                {
                    Format(display, sizeof(display), "Shake %T", g_sCustomKeysPref[param1][1]==0 ? "Off" : "On", param1);
                    return RedrawMenuItem(display);
                }
                case 'j':
                {
                    Format(display, sizeof(display), "Hint %T", g_CellRequestsPref[param1].hint ? "On" : "Off", param1);
                    return RedrawMenuItem(display);
                }
            }
        }
        case MenuAction_Select:
        {
            switch(param2)
        	{
            	case 0: // PTG
                {
                    RequestGuide(param1,g_CellRequestsPref[param1].duration,g_CellRequestsPref[param1].backward,true,g_CellRequestsPref[param1].hint);
                }
                case 1: // Duration
                {
                    float duration = g_CellRequestsPref[param1].duration;
                    duration -= 3.0;
                    if (duration<3.0) duration = 9.0;
                    g_CellRequestsPref[param1].duration = duration;
                }
                case 2: // Backward
                {
                    g_CellRequestsPref[param1].backward = !g_CellRequestsPref[param1].backward;
                }
                case 3: // Style
                {
                    SwitchTripleKey(param1,0,'c',0,'w');
                }   
                case 4: // Delay
                {
                    SwitchBoolKey(param1,4,'d');
                }
                case 5: // Sound
                {
                    SwitchBoolKey(param1,5,'s');
                }
                case 6: // Size
                {
                    SwitchTripleKey(param1,2,'s',0,'l');
                }
                case 7: // Arrow
                {
                    SwitchBoolKey(param1,3,'a');
                }
                case 8: // Shake
                {
                    SwitchBoolKey(param1,1,'s');
                }
                case 9: // Hint
                {
                    g_CellRequestsPref[param1].hint = !g_CellRequestsPref[param1].hint;
                }
                case 10: // Reset
                {
                    ResetClientSettings(param1);
                }
        	}
            g_CellRequestsPref[param1].menu_opened = true;
            RegisterClientPrefs(param1);
            DisplayMenuAtItem(menu_ptg,param1,(param2/7)*7,MENU_TIME_FOREVER);
        }
    }
	return 0;
}

stock void SwitchBoolKey(const int client, const int i, const char val)
{
    if (g_sCustomKeysPref[client][i]==val) g_sCustomKeysPref[client][i] = 0;
    else g_sCustomKeysPref[client][i] = val;
}

stock void SwitchTripleKey(const int client, const int i, const char val1, const char val2, const char val3)
{
    if (g_sCustomKeysPref[client][i]==val1) g_sCustomKeysPref[client][i] = val2;
    else if (g_sCustomKeysPref[client][i]==val2) g_sCustomKeysPref[client][i] = val3;
    else g_sCustomKeysPref[client][i] = val1;
}