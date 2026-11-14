#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#define CLEAR_CARRIED_DELAY 0.85

float g_fProtectUntil[MAXPLAYERS + 1] = { 0.0, ... };

public Plugin myinfo =
{
    name        = "L4D2 Charger Carry FF Fix",
    author      = "Rainy",
    description = "차저에게 끌려가는 생존자에 대한 팀킬을 방지합니다.",
    version     = "1.2.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_charger_carry_ff_fix"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    HookEvent("charger_carry_end", Event_ChargerCarryEnd);

    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
}

public void OnClientPutInServer(int client)
{
    g_fProtectUntil[client] = 0.0;
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    g_fProtectUntil[client] = 0.0;
    SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i < sizeof(g_fProtectUntil); i++)
        g_fProtectUntil[i] = 0.0;
}

void Event_ChargerCarryEnd(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (victim > 0 && victim <= MaxClients)
        g_fProtectUntil[victim] = GetGameTime() + CLEAR_CARRIED_DELAY;
}

Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (victim != attacker && IsValidSurvivor(victim) && IsValidSurvivor(attacker)
        && (IsCarried(victim) || GetGameTime() < g_fProtectUntil[victim]))
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

// 이벤트 대신 넷프롭을 읽어서 charger_carry_end가 빠져도 보호 상태가 남지 않는다
bool IsCarried(int client)
{
    return GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
