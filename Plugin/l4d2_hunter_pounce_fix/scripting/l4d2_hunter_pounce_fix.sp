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
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_hunter_pounce_fix"
};

public void OnPluginStart()
{
    GameData hGameData = new GameData(GAMEDATA);
    if (hGameData == null)
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);

    g_hSetAbsOrigin        = PrepSetAbsCall(hGameData, "CBaseEntity::SetAbsOrigin");
    g_hSetAbsVelocity      = PrepSetAbsCall(hGameData, "CBaseEntity::SetAbsVelocity");

    g_hPatchSetAbsVelocity = MemoryPatch.CreateFromConf(hGameData, "CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity");
    delete hGameData;

    if (g_hPatchSetAbsVelocity == null)
        SetFailState("Failed to create patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\".");
    if (!g_hPatchSetAbsVelocity.Validate())
        SetFailState("Patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\" verify failed. Gamedata is outdated.");
    if (!g_hPatchSetAbsVelocity.Enable())
        SetFailState("Failed to enable patch \"CTerrorPlayer::UpdatePounce::SkipSetAbsVelocity\".");

    // Late load
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (IsClientInGame(iClient))
            OnClientPutInServer(iClient);
    }
}

Handle PrepSetAbsCall(GameData hGameData, const char[] sName)
{
    StartPrepSDKCall(SDKCall_Entity);
    if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, sName))
        SetFailState("Failed to find signature \"%s\".", sName);
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer);

    Handle hCall = EndPrepSDKCall();
    if (hCall == null)
        SetFailState("Failed to prep SDKCall \"%s\".", sName);
    return hCall;
}

public void OnClientPutInServer(int iClient)
{
    SDKHook(iClient, SDKHook_PostThink, PostThink_Hunter);
}

void PostThink_Hunter(int iHunter)
{
    if (!IsPlayerAlive(iHunter) || GetClientTeam(iHunter) != 3)
        return;

    int iVictim = GetEntPropEnt(iHunter, Prop_Send, "m_pounceVictim");
    if (iVictim < 1 || !IsPlayerAlive(iVictim) || GetEntPropEnt(iVictim, Prop_Send, "m_pounceAttacker") != iHunter)
        return;

    // 피해자의 위치와 속도를 그대로 복사해 클라이언트 보간과 렉 보상이 피해자 기준으로 맞도록 한다
    float vecOrigin[3], vecVelocity[3];
    GetEntPropVector(iVictim, Prop_Data, "m_vecAbsOrigin", vecOrigin);
    GetEntPropVector(iVictim, Prop_Data, "m_vecAbsVelocity", vecVelocity);

    // TeleportEntity는 헌터 외곽선을 깜빡이게 하므로 직접 호출한다
    SDKCall(g_hSetAbsOrigin, iHunter, vecOrigin);
    SDKCall(g_hSetAbsVelocity, iHunter, vecVelocity);
}
