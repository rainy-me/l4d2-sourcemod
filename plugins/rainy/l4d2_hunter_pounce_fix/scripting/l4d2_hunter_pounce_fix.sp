#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sourcescramble>

#define GAMEDATA "l4d2_hunter_pounce_fix"

Handle      g_hSetAbsOrigin;
Handle      g_hSetAbsVelocity;
MemoryPatch g_hPatchSetAbsVelocity;

public Plugin myinfo =
{
    name        = "L4D2 Hunter Pounce Fix",
    author      = "Rainy",
    description = "헌터가 생존자를 덮치는 동안 헌터의 위치와 속도를 생존자에 맞춰 어긋나 보이지 않게 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_hunter_pounce_fix"
};

public void OnPluginStart()
{
    GameData gameData = new GameData(GAMEDATA);
    if (gameData == null)
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);

    g_hSetAbsOrigin        = PrepSetAbsCall(gameData, "CBaseEntity::SetAbsOrigin");
    g_hSetAbsVelocity      = PrepSetAbsCall(gameData, "CBaseEntity::SetAbsVelocity");

    g_hPatchSetAbsVelocity = MemoryPatch.CreateFromConf(gameData, "CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity");
    delete gameData;

    if (g_hPatchSetAbsVelocity == null)
        SetFailState("Failed to create patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\".");
    if (!g_hPatchSetAbsVelocity.Validate())
        SetFailState("Patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\" verify failed. Gamedata is outdated.");
    if (!g_hPatchSetAbsVelocity.Enable())
        SetFailState("Failed to enable patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\".");

    // Late load
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PostThink, PostThink_Hunter);
}

void PostThink_Hunter(int hunter)
{
    if (!IsPlayerAlive(hunter) || GetClientTeam(hunter) != 3)
        return;

    int victim = GetEntPropEnt(hunter, Prop_Send, "m_pounceVictim");
    if (victim < 1 || !IsPlayerAlive(victim) || GetEntPropEnt(victim, Prop_Send, "m_pounceAttacker") != hunter)
        return;

    // 피해자의 위치와 속도를 그대로 복사해 클라이언트 보간과 렉 보상이 피해자 기준으로 맞도록 한다
    float origin[3], velocity[3];
    GetEntPropVector(victim, Prop_Data, "m_vecAbsOrigin", origin);
    GetEntPropVector(victim, Prop_Data, "m_vecAbsVelocity", velocity);

    // TeleportEntity는 헌터 외곽선을 깜빡이게 하므로 직접 호출한다
    SDKCall(g_hSetAbsOrigin, hunter, origin);
    SDKCall(g_hSetAbsVelocity, hunter, velocity);
}

Handle PrepSetAbsCall(GameData gameData, const char[] name)
{
    StartPrepSDKCall(SDKCall_Entity);
    if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, name))
        SetFailState("Failed to find signature \"%s\".", name);
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);

    Handle call = EndPrepSDKCall();
    if (call == null)
        SetFailState("Failed to prep SDKCall \"%s\".", name);
    return call;
}
