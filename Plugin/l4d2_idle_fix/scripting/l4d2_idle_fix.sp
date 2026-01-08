#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Idle Fix",
    author      = "Rainy",
    description = "유휴 명령 미인식 문제를 해결합니다.",
    version     = "1.2.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_fix"
};

ConVar g_hCoolDown;
ConVar g_hCoolDownMessage;
float  g_fLastUseTime[MAXPLAYERS + 1] = { 0.0, ... };

public void OnPluginStart()
{
    g_hCoolDown        = CreateConVar("l4d2_idle_fix_cooldown_time", "0.25",
                                      "Cooldown time in seconds a player can use the idle command again.",
                                      FCVAR_NOTIFY, true, 0.0);
    g_hCoolDownMessage = CreateConVar("l4d2_idle_fix_cooldown_message", "0",
                                      "Enable/Disable cooldown message when a player tries to use the idle command during cooldown.\n1 = Enable, 0 = Disable.",
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

    if (GetEngineTime() < g_fLastUseTime[client] + g_hCoolDown.FloatValue)
    {
        if (g_hCoolDownMessage.BoolValue)
        {
            PrintToChat(client, "Idle Cooldown.");
        }
        return Plugin_Handled;
    }

    L4D_GoAwayFromKeyboard(client);
    g_fLastUseTime[client] = GetEngineTime();
    return Plugin_Handled;
}