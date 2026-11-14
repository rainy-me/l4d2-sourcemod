#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <multicolors>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Unstuck",
    author      = "Rainy",
    description = "끼인 플레이어가 스스로 탈출할 수 있는 명령을 제공합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_unstuck"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_unstuck.phrases");
    RegConsoleCmd("sm_stuck", Cmd_Stuck, "Teleport myself out of a stuck position.");
}

Action Cmd_Stuck(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Handled;

    L4D_WarpToValidPositionIfStuck(client);
    CPrintToChat(client, "%t", "Unstuck");
    return Plugin_Handled;
}
