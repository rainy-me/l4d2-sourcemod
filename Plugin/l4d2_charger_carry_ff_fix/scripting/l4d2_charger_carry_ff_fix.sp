#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

bool g_bIsCarried[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 Charger Carry FF Fix",
    author      = "Rainy",
    description = "차저에게 끌려가는 생존자에 대한 팀킬을 방지합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_charger_carry_ff_fix"
};

public void OnPluginStart()
{
    HookEvent("charger_carry_start", Event_ChargerCarryStart);
    HookEvent("charger_carry_end", Event_ChargerCarryEnd);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
}

public void OnClientPutInServer(int client)
{
    g_bIsCarried[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_bIsCarried[client] = false;
}

void Event_ChargerCarryStart(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (IsValidSurvivor(victim))
    {
        g_bIsCarried[victim] = true;
    }
}

void Event_ChargerCarryEnd(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (IsValidSurvivor(victim))
    {
        g_bIsCarried[victim] = false;
    }
}

Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (IsValidSurvivor(victim) && IsValidSurvivor(attacker) && g_bIsCarried[victim])
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}