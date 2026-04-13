#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define ZC_HUNTER     3
#define ZC_JOCKEY     5
#define ZC_TANK       8

// Delay before re-enabling attack after stagger ends
#define RENABLE_DELAY 0.5

// Per-client time when stagger/airborne state ended; 0.0 = not in cooldown
float g_fBlockEndTime[MAXPLAYERS + 1] = { 0.0, ... };

public Plugin myinfo =
{
    name        = "L4D2 AI Stagger Claw Fix",
    author      = "Rainy",
    description = "AI SI가 비틀거리거나 공중에 떠 있는 동안 긁기공격을 하지 못하도록 방지합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_ai_stagger_claw_fix"
};

public void OnClientDisconnect(int client)
{
    g_fBlockEndTime[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
    if (!IsFakeClient(client) || GetClientTeam(client) != 3 || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }

    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zClass == ZC_TANK)
    {
        return Plugin_Continue;
    }

    bool bShouldBlock = false;

    // Check 1: currently staggering
    if (GetEntPropFloat(client, Prop_Send, "m_staggerTimer", 1) > -1.0)
    {
        bShouldBlock = true;
    }
    // Check 2: hunter or jockey airborne (deadstop etc.)
    if (!bShouldBlock && !(GetEntityFlags(client) & FL_ONGROUND) && (zClass == ZC_HUNTER || zClass == ZC_JOCKEY))
    {
        bShouldBlock = true;
    }

    if (bShouldBlock)
    {
        // Actively staggering/airborne — block attack and keep refreshing the end time
        g_fBlockEndTime[client] = GetGameTime() + RENABLE_DELAY;
        buttons &= ~IN_ATTACK2;
        return Plugin_Changed;
    }

    // Still within the cooldown window after stagger ended
    if (g_fBlockEndTime[client] > GetGameTime())
    {
        buttons &= ~IN_ATTACK2;
        return Plugin_Changed;
    }

    g_fBlockEndTime[client] = 0.0;
    return Plugin_Continue;
}
