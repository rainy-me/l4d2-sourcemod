#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define HUNTER                     3
#define DEBUG                      0
#define HUNTERCROUCHTRACKING_TIMER 1.0

static char sHunterSound[][] = {
    "player/hunter/voice/idle/hunter_stalk_01.wav",
    "player/hunter/voice/idle/hunter_stalk_04.wav",
    "player/hunter/voice/idle/hunter_stalk_05.wav",
    "player/hunter/voice/idle/hunter_stalk_06.wav",
    "player/hunter/voice/idle/hunter_stalk_07.wav",
    "player/hunter/voice/idle/hunter_stalk_08.wav",
    "player/hunter/voice/idle/hunter_stalk_09.wav"
};
bool       isHunter[MAXPLAYERS + 1] = { false, ... };
static int g_iOffsetFallVelocity    = -1;

public Plugin myinfo =
{
    name        = "Hunter Crouch Sounds",
    author      = "Harry",
    description = "Forces silent but crouched hunters to emit sounds",
    version     = "1.6-2025/5/5",
    url         = "https://steamcommunity.com/profiles/76561198026784913/"
};

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    g_iOffsetFallVelocity = FindSendPropInfo("CTerrorPlayer", "m_flFallVelocity");
    if (g_iOffsetFallVelocity <= 0)
    {
        ThrowError("Unable to find fall velocity offset!");
    }
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(sHunterSound); i++)
    {
        PrecacheSound(sHunterSound[i]);
    }
    for (int i = 0; i <= MAXPLAYERS; i++)
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
    if (!isHunter[client])
    {
        return Plugin_Stop;
    }

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
        PrintToChatAll("0.1s later check again");
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
        int rndPick = GetRandomInt(0, sizeof(sHunterSound) - 1);
        EmitSoundToAll(sHunterSound[rndPick], client, SNDCHAN_VOICE, 85);
        PrintToChatAll("Emit sound!");
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
    if (IsClientAndInGame(hasvictim) && GetClientTeam(hasvictim) == 2)
    {
        return true;
    }
    return false;
}

bool IsClientAndInGame(int index)
{
    return IsClient(index) && IsClientInGame(index);
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}