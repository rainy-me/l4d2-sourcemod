#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Idle Fix",
    author      = "Rainy",
    description = "유휴 명령 미인식 문제를 해결합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_fix"
};

public void OnPluginStart()
{
    RegConsoleCmd("go_away_from_keyboard", Cmd_ForceIdle, "Override with forced idle mode.");
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

    L4D_GoAwayFromKeyboard(client);
    return Plugin_Handled;
}