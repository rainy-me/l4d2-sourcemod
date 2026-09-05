#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 No Melee FF",
    author      = "Rainy",
    description = "근접무기 팀킬을 차단합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_melee_ff"
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

    // 근접무기/전기톱 피해는 inflictor가 무기 엔티티
    if (inflictor <= MaxClients || !IsValidEntity(inflictor))
    {
        return Plugin_Continue;
    }

    char classname[32];
    GetEntityClassname(inflictor, classname, sizeof(classname));
    // 전기톱도 막으려면 || StrEqual(classname, "weapon_chainsaw") 추가
    if (StrEqual(classname, "weapon_melee"))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
