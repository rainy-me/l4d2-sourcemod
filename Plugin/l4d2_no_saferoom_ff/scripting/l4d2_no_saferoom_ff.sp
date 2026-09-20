#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 No Saferoom FF",
    author      = "Rainy",
    description = "은신처 안에 있는 생존자에 대한 팀킬을 차단합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_saferoom_ff"
};

public void OnPluginStart()
{
    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (victim == attacker || !IsValidSurvivor(victim) || !IsValidSurvivor(attacker))
    {
        return Plugin_Continue;
    }

    if (L4D_IsInFirstCheckpoint(victim) || L4D_IsInLastCheckpoint(victim))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
