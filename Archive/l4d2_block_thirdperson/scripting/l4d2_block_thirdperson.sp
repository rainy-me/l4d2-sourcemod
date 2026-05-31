#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Block Thirdperson",
    author      = "Rainy",
    description = "3인칭 모드를 차단합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Archive/l4d2_block_thirdperson"
};

public void OnPluginStart()
{
    RegConsoleCmd("thirdpersonshoulder", Cmd_BlockThirdPerson);
}

Action Cmd_BlockThirdPerson(int client, int args)
{
    return Plugin_Handled;
}
