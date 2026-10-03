#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 No Ledge Hang",
    author      = "Rainy",
    description = "생존자가 난간에 매달리는 기능을 제거합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_ledge_hang"
};

public Action L4D_OnLedgeGrabbed(int client)
{
    return Plugin_Handled;
}
