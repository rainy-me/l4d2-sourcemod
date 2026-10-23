#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define GAMEDATA "l4d2_witch_update_rate"

ConVar    g_hUpdateRate;
Handle    g_hMyNextBotPointer;
int       g_iFlaggedForUpdate;
ArrayList g_hWitches;
float     g_fUpdateDebt;

public Plugin myinfo =
{
    name        = "L4D2 Witch Update Rate",
    author      = "Rainy",
    description = "nb_update_frequency와 관계없이 윗치의 NextBot 업데이트 빈도를 별도로 설정합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_witch_update_rate"
};

public void OnPluginStart()
{
    GameData hGameData = new GameData(GAMEDATA);
    if (hGameData == null)
    {
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);
    }

    StartPrepSDKCall(SDKCall_Entity);
    if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseEntity::MyNextBotPointer"))
    {
        SetFailState("Failed to get offset 'CBaseEntity::MyNextBotPointer'.");
    }
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    g_hMyNextBotPointer = EndPrepSDKCall();

    g_iFlaggedForUpdate = hGameData.GetOffset("INextBot::m_isFlaggedForUpdate");
    delete hGameData;
    if (g_iFlaggedForUpdate == -1)
    {
        SetFailState("Failed to get offset 'INextBot::m_isFlaggedForUpdate'.");
    }

    g_hUpdateRate = CreateConVar(
        "l4d2_witch_update_rate", "30.0",
        "Witch NextBot updates per second (capped at server tickrate)",
        _, true, 10.0, true, 100.0);
    AutoExecConfig(true, "l4d2_witch_update_rate");

    g_hWitches = new ArrayList();

    // Late load
    int witch  = -1;
    while ((witch = FindEntityByClassname(witch, "witch")) != -1)
    {
        g_hWitches.Push(witch);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (strcmp(classname, "witch") == 0)
    {
        g_hWitches.Push(entity);
    }
}

public void OnEntityDestroyed(int entity)
{
    int index = g_hWitches.FindValue(entity);
    if (index != -1)
    {
        g_hWitches.Erase(index);
    }
}

public void OnGameFrame()
{
    // 틱레이트가 설정값의 배수가 아니어도(100/30 등) 초당 횟수가 맞도록 누적해서 센다.
    g_fUpdateDebt += g_hUpdateRate.FloatValue * GetTickInterval();
    if (g_fUpdateDebt < 1.0)
    {
        return;
    }
    g_fUpdateDebt = g_fUpdateDebt >= 2.0 ? 0.0 : g_fUpdateDebt - 1.0;

    // NextBotManager가 nb_update_frequency 주기에만 세우는 플래그를 윗치에게 직접 세운다.
    for (int i = 0; i < g_hWitches.Length; i++)
    {
        Address nb = SDKCall(g_hMyNextBotPointer, g_hWitches.Get(i));
        if (nb != Address_Null)
        {
            StoreToAddress(nb + view_as<Address>(g_iFlaggedForUpdate), 1, NumberType_Int8);
        }
    }
}
