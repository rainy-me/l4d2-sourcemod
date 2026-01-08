#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Force Idle",
    author      = "Rainy",
    description = "강제 유휴모드 전환",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_force_idle"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_idle", Cmd_ForceIdle, "Force the player into idle mode");
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

    if (!L4D_GoAwayFromKeyboard(client))
    {
        PrintToChat(client, "ForceIdle: Failed L4D_GoAwayFromKeyboard, trying FakeClientCommandEx.");
        FakeClientCommandEx(client, "go_away_from_keyboard");
    }
    return Plugin_Handled;
}