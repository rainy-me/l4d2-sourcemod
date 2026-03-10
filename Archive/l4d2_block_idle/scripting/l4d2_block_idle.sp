#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Block Idle",
    author      = "Rainy",
    description = "유휴 모드를 차단합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_block_idle"
};

public void OnPluginStart()
{
    RegConsoleCmd("go_away_from_keyboard", Cmd_BlockIdle);
    FindConVar("director_afk_timeout").IntValue = 9999;
}

Action Cmd_BlockIdle(int client, int args)
{
    return Plugin_Handled;
}
