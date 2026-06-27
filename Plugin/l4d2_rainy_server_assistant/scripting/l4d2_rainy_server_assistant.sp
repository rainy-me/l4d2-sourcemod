#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define RESPAWN_DELAY 3.0

public Plugin myinfo =
{
    name        = "L4D2 Rainy Server Assistant",
    author      = "Rainy",
    description = "Rainy 서버 자동화 플러그인",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_rainy_server_assistant"
};

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    CreateTimer(RESPAWN_DELAY, Timer_RespawnNewPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void Timer_RespawnNewPlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || IsFakeClient(client) || IsPlayerAlive(client) || GetClientTeam(client) != 2)
    {
        return;
    }

    L4D_RespawnPlayer(client);
    GivePlayerItem(client, "weapon_shotgun_chrome");
    GivePlayerItem(client, "weapon_first_aid_kit");

    int target = GetLowestFlowSurvivor(client);
    if (target != -1)
    {
        float pos[3], ang[3];
        GetClientAbsOrigin(target, pos);
        GetClientAbsAngles(target, ang);
        TeleportEntity(client, pos, ang);
        L4D_WarpToValidPositionIfStuck(client);
    }
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != 2)
        {
            continue;
        }
        if (IsIdlePlayer(i))
        {
            continue;
        }

        RemovePistol(i);
        ForcePlayerSuicide(i);
    }
}

// Helpers
// ------------------------------------
int GetLowestFlowSurvivor(int exclude)
{
    int   best = -1;
    float bestFlow;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == exclude || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != 2)
        {
            continue;
        }

        float flow = L4D2Direct_GetFlowDistance(i);
        if (best == -1 || flow < bestFlow)
        {
            best     = i;
            bestFlow = flow;
        }
    }

    return best;
}

void RemovePistol(int client)
{
    int weapon = GetPlayerWeaponSlot(client, 1);
    if (weapon == -1)
    {
        return;
    }

    char classname[32];
    GetEntityClassname(weapon, classname, sizeof(classname));
    if (StrEqual(classname, "weapon_pistol"))
    {
        RemovePlayerItem(client, weapon);
    }
}

bool IsIdlePlayer(int client)
{
    return GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") > 0;
}

bool IsValidClient(int index)
{
    return index > 0 && index <= MaxClients && IsClientInGame(index);
}
