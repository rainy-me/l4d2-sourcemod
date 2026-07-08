#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Suicide",
    author      = "Rainy",
    description = "admin 권한 없이도 자살 명령을 사용할 수 있도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_suicide"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_kill", Cmd_Kill);
}

Action Cmd_Kill(int client, int args)
{
    if (args > 0)
    {
        return Plugin_Continue;
    }
    if (client == 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    ForcePlayerSuicide(client);
    return Plugin_Handled;
}
