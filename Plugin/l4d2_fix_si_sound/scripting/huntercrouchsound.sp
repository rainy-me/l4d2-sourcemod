#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define HUNTER                     3
#define DEBUG                      0
#define HUNTERCROUCHTRACKING_TIMER 1.0

static char sHunterSound_L4D2[][] = {
    "player/hunter/voice/idle/hunter_stalk_01.wav",
    "player/hunter/voice/idle/hunter_stalk_04.wav",
    "player/hunter/voice/idle/hunter_stalk_05.wav",
    "player/hunter/voice/idle/hunter_stalk_06.wav",
    "player/hunter/voice/idle/hunter_stalk_07.wav",
    "player/hunter/voice/idle/hunter_stalk_08.wav",
    "player/hunter/voice/idle/hunter_stalk_09.wav"
};

bool        isHunter[MAXPLAYERS + 1];
static int  g_iOffsetFallVelocity    = -1;
static char CLASSNAME_TERRORPLAYER[] = "CTerrorPlayer";
static char NETPROP_FALLVELOCITY[]   = "m_flFallVelocity";

public Plugin myinfo =
{
    name        = "Hunter Crouch Sounds",
    author      = "Harry",
    description = "Forces silent but crouched hunters to emitt sounds",
    version     = "1.6-2025/5/5",
    url         = "https://steamcommunity.com/profiles/76561198026784913/"
};

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", event_RoundStart);
    g_iOffsetFallVelocity = FindSendPropInfo(CLASSNAME_TERRORPLAYER, NETPROP_FALLVELOCITY);
    if (g_iOffsetFallVelocity <= 0) ThrowError("Unable to find fall velocity offset!");
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(sHunterSound_L4D2); i++)
    {
        PrecacheSound(sHunterSound_L4D2[i]);
    }
}

void event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    int i;
    for (i = 0; i <= MAXPLAYERS; ++i)
    {
        isHunter[i] = false;
    }
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientAndInGame(client) || GetClientTeam(client) != 3)
    {
        return;
    }

    if (GetEntProp(client, Prop_Send, "m_zombieClass") == HUNTER)
    {
        isHunter[client] = true;
        CreateTimer(HUNTERCROUCHTRACKING_TIMER, HunterCrouchTracking, client, TIMER_REPEAT);
    }
}

Action HunterCrouchTracking(Handle timer, any client)
{
    if (!isHunter[client]) { return Plugin_Stop; }

    if (!IsClientAndInGame(client) || GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_zombieClass") != HUNTER || !IsPlayerAlive(client))
    {
        isHunter[client] = false;
        return Plugin_Stop;
    }

    if (HasTarget(client))
    {
        return Plugin_Continue;
    }

    if (GetClientButtons(client) & IN_DUCK)
    {
        return Plugin_Continue;
    }
    int ducked = GetEntProp(client, Prop_Send, "m_bDucked");
    if (ducked && GetEntDataFloat(client, g_iOffsetFallVelocity) == 0.0)
    {
#if DEBUG
        PrintToChatAll("0.1s later check again");
#endif
        CreateTimer(0.1, HunterCrouchReallyCheck, client, _);
    }

    return Plugin_Continue;
}

Action HunterCrouchReallyCheck(Handle timer, any client)
{
    if (!IsClientAndInGame(client) || GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_zombieClass") != HUNTER || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }
    if (GetClientButtons(client) & IN_DUCK)
    {
        return Plugin_Continue;
    }
    int ducked = GetEntProp(client, Prop_Send, "m_bDucked");
    if (ducked && GetEntDataFloat(client, g_iOffsetFallVelocity) == 0.0)
    {
        int rndPick = GetRandomInt(0, sizeof(sHunterSound_L4D2) - 1);
        EmitSoundToAll(sHunterSound_L4D2[rndPick], client, SNDCHAN_VOICE, 85);

#if DEBUG
        PrintToChatAll("Emit sound!");
#endif
    }
    return Plugin_Continue;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim       = GetEventInt(event, "userid");
    int client       = GetClientOfUserId(victim);
    isHunter[client] = false;
}

bool HasTarget(int hunter)
{
    int hasvictim = GetEntPropEnt(hunter, Prop_Send, "m_pounceVictim");
    if (IsSurvivors(hasvictim))
    {
        return true;
    }
    return false;
}

bool IsSurvivors(int client)
{
    return IsClientAndInGame(client) && GetClientTeam(client) == 2;
}

bool IsClientAndInGame(int index)
{
    return IsClient(index) && IsClientInGame(index);
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}