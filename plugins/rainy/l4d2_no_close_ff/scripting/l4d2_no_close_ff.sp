#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>

ConVar g_hConVarRadius;
ConVar g_hConVarVertGap;

public Plugin myinfo =
{
    name        = "L4D2 No Close FF",
    author      = "Rainy",
    description = "팀원이 너무 가까이 있을 때 팀킬을 차단합니다.",
    version     = "1.0.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_no_close_ff"
};

public void OnPluginStart()
{
    g_hConVarRadius = CreateConVar(
        "l4d2_no_close_ff_radius", "30",
        "Block friendly fire damage when the attacker and victim are within this horizontal distance (units)",
        FCVAR_NOTIFY, true, 0.0);
    g_hConVarVertGap = CreateConVar(
        "l4d2_no_close_ff_vgap", "70",
        "Only block when the vertical height difference between the two survivors is at or below this value (units)",
        FCVAR_NOTIFY, true, 0.0);
    AutoExecConfig(true, "l4d2_no_close_ff");

    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (victim == attacker || !IsValidSurvivor(victim) || !IsValidSurvivor(attacker))
        return Plugin_Continue;

    if (L4D_IsPlayerIncapacitated(victim))
        return Plugin_Continue;

    float victimPos[3];
    float attackerPos[3];
    GetClientAbsOrigin(victim, victimPos);
    GetClientAbsOrigin(attacker, attackerPos);

    // 차이(delta) 계산
    float dx      = attackerPos[0] - victimPos[0];
    float dy      = attackerPos[1] - victimPos[1];
    float dz      = attackerPos[2] - victimPos[2];

    // 수평 거리(제곱)와 수직 거리(절댓값) 분리 계산
    float horizSq = dx * dx + dy * dy;
    float vert    = FloatAbs(dz);

    // 원기둥 판정: 수평 거리 + 수직 높이 차 분리
    float r       = g_hConVarRadius.FloatValue;
    if (horizSq <= r * r && vert <= g_hConVarVertGap.FloatValue)
        return Plugin_Handled;

    return Plugin_Continue;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
