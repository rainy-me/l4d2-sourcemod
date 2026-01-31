#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Idle Adrenaline Fix",
    author      = "Rainy",
    description = "플레이어가 유휴 모드에서 복귀할 때 아드레날린 효과를 유지하도록 수정합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_adrenaline_fix"
};

ConVar g_hAdrenalineDuration;
float  g_fAdrenalineEndTime[MAXPLAYERS + 1] = { 0.0, ... };

public void OnPluginStart()
{
    g_hAdrenalineDuration = FindConVar("adrenaline_duration");

    HookEvent("adrenaline_used", Event_AdrenalineUsed);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);    // 유휴 복귀
    HookEvent("player_incapacitated", Event_ResetAdrenalineEndTime);
    HookEvent("player_death", Event_ResetAdrenalineEndTime);
    HookEvent("round_end", Event_ResetAdrenalineEndTime);
}

public void OnClientPutInServer(int client)
{
    g_fAdrenalineEndTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
    g_fAdrenalineEndTime[client] = 0.0;
}

void Event_ResetAdrenalineEndTime(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    g_fAdrenalineEndTime[client] = 0.0;
}

void Event_AdrenalineUsed(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    g_fAdrenalineEndTime[client] = GetGameTime() + g_hAdrenalineDuration.FloatValue;
}

void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    float fCurrentTime = GetGameTime();
    if (fCurrentTime < g_fAdrenalineEndTime[client])
    {
        L4D2_UseAdrenaline(client, g_fAdrenalineEndTime[client] - fCurrentTime, false, false);
    }
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
