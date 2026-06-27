#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 No DeathFall Cam",
    author      = "Rainy",
    description = "추락 시 카메라 시점 전환을 차단합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_deathfall_cam"
};

public Action L4D_OnFatalFalling(int client, int camera)
{
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2)
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}
