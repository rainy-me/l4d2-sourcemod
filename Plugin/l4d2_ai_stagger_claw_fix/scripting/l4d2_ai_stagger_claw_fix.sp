#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define ZC_HUNTER     3
#define ZC_JOCKEY     5
#define ZC_TANK       8

#define TICK_INTERVAL 0.033
// Delay before re-enabling attack after stagger ends
#define RENABLE_DELAY 0.5

Handle g_hTimer;
bool   g_bBlocked[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 AI Stagger Claw Fix",
    author      = "Rainy",
    description = "AI SI가 비틀거리거나 공중에 떠 있는 동안 긁기공격을 하지 못하도록 방지합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_ai_stagger_claw_fix"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_hTimer = null;
}

public void OnClientDisconnect(int client)
{
    g_bBlocked[client] = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetBlockedState();
    CreateThinkTimer();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    KillThinkTimer();
    ResetBlockedState();
}

void ResetBlockedState()
{
    for (int i = 0; i < sizeof(g_bBlocked); i++)
    {
        g_bBlocked[i] = false;
    }
}

void CreateThinkTimer()
{
    KillThinkTimer();
    g_hTimer = CreateTimer(TICK_INTERVAL, Timer_StaggerCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void KillThinkTimer()
{
    if (g_hTimer != null)
    {
        delete g_hTimer;
    }
}

Action Timer_StaggerCheck(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) == 2 || !IsPlayerAlive(i) || !IsFakeClient(i))
        {
            continue;
        }

        int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
        if (zClass == ZC_TANK)
        {
            continue;
        }

        bool bShouldBlock = false;
        // Check 1: currently staggering (m_staggerTimer remaining > -1.0)
        if (GetEntPropFloat(i, Prop_Send, "m_staggerTimer", 1) > -1.0)
        {
            bShouldBlock = true;
        }
        // Check 2: hunter or jockey not on ground (airborne after deadstop etc.)
        if (!bShouldBlock && !(GetEntityFlags(i) & FL_ONGROUND) && (zClass == ZC_HUNTER || zClass == ZC_JOCKEY))
        {
            bShouldBlock = true;
        }

        if (bShouldBlock)
        {
            if (!g_bBlocked[i])
            {
                g_bBlocked[i] = true;
                int disabled  = GetEntProp(i, Prop_Data, "m_afButtonDisabled");
                SetEntProp(i, Prop_Data, "m_afButtonDisabled", disabled | IN_ATTACK2);
            }
        }
        else if (g_bBlocked[i])
        {
            g_bBlocked[i] = false;
            // Re-enable after a short delay so the stagger animation fully finishes
            CreateTimer(RENABLE_DELAY, Timer_ReEnableAttack, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    return Plugin_Continue;
}

void Timer_ReEnableAttack(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    int disabled = GetEntProp(client, Prop_Data, "m_afButtonDisabled");
    SetEntProp(client, Prop_Data, "m_afButtonDisabled", disabled & ~IN_ATTACK2);
}

bool IsClient(int client)
{
    return client > 0 && client <= MaxClients;
}
