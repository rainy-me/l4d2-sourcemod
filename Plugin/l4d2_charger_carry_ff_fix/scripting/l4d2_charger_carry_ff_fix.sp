#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#define CLEAR_CARRIED_DELAY 0.85

bool g_bIsCarried[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 Charger Carry FF Fix",
    author      = "Rainy",
    description = "차저에게 끌려가는 생존자에 대한 팀킬을 방지합니다.",
    version     = "1.2.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_charger_carry_ff_fix"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    HookEvent("charger_carry_start", Event_ChargerCarryStart);
    HookEvent("charger_carry_end", Event_ChargerCarryEnd);

    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    g_bIsCarried[client] = false;
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    g_bIsCarried[client] = false;
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i < sizeof(g_bIsCarried); i++)
    {
        g_bIsCarried[i] = false;
    }
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
    if (victim > 0 && victim <= MaxClients)
    {
        CreateTimer(CLEAR_CARRIED_DELAY, Timer_ClearCarried, event.GetInt("victim"), TIMER_FLAG_NO_MAPCHANGE);
    }
}

void Timer_ClearCarried(Handle timer, int userid)
{
    int victim = GetClientOfUserId(userid);
    if (victim > 0 && victim <= MaxClients)
    {
        g_bIsCarried[victim] = false;
    }
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (victim != attacker && IsValidSurvivor(victim) && IsValidSurvivor(attacker) && g_bIsCarried[victim])
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
