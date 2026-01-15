#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Idle Fix",
    author      = "Rainy",
    description = "유휴 명령 미인식 문제를 해결합니다.",
    version     = "1.3.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_fix"
};

ConVar g_hIdleMessage;
ConVar g_hCooldownTime;
ConVar g_hCooldownMessage;
float  g_fLastUseTime[MAXPLAYERS + 1] = { 0.0, ... };

public void OnPluginStart()
{
    LoadTranslations("l4d2_idle_fix.phrases");

    g_hIdleMessage     = CreateConVar("l4d2_idle_fix_idle_message", "0",
                                      "ON/OFF idle message. (1=ON, 0=OFF)",
                                      FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCooldownTime    = CreateConVar("l4d2_idle_fix_cooldown_time", "0.25",
                                      "Cooldown time in seconds a player can use the idle command again.",
                                      FCVAR_NOTIFY, true, 0.0);
    g_hCooldownMessage = CreateConVar("l4d2_idle_fix_cooldown_message", "0",
                                      "ON/OFF cooldown message. (1=ON, 0=OFF)",
                                      FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_idle_fix");

    RegConsoleCmd("go_away_from_keyboard", Cmd_ForceIdle, "Override with forced idle mode.");
}

public void OnClientPutInServer(int client)
{
    g_fLastUseTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
    g_fLastUseTime[client] = 0.0;
}

Action Cmd_ForceIdle(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }
    if (GetClientTeam(client) != L4D_TEAM_SURVIVOR)
    {
        return Plugin_Handled;
    }

    if (GetEngineTime() < g_fLastUseTime[client] + g_hCooldownTime.FloatValue)
    {
        if (g_hCooldownMessage.BoolValue)
        {
            PrintToChat(client, "%t", "Cooldown Message");
        }
        return Plugin_Handled;
    }

    L4D_GoAwayFromKeyboard(client);
    if (g_hIdleMessage.BoolValue)
    {
        PrintToChatAll("%t", "Idle Message", client);
    }
    g_fLastUseTime[client] = GetEngineTime();
    return Plugin_Handled;
}