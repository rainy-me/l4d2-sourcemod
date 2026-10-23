#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define GAMEDATA "l4d2_witch_update_rate"

Handle    g_hMyNextBotPointer;
int       g_iFlaggedForUpdate;
ConVar    g_hUpdateRate;
ArrayList g_hWitches;

public Plugin myinfo =
{
    name        = "L4D2 Witch Update Rate",
    author      = "Rainy",
    description = "nb_update_frequency와 관계없이 윗치의 NextBot 업데이트 빈도를 별도로 설정합니다.",
    version     = "1.0.1",
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
        "l4d2_witch_update_rate", "30",
        "Witch NextBot updates per second (capped at server tickrate)",
        _, true, 10.0);
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
    // 1초(tickrate틱)를 l4d2_witch_update_rate 값만큼의 구간으로 나누고, 새 구간이 시작되는 틱에만 플래그를 세운다.
    // tickcount 기준이라 설정값이 10의 배수면 NextBotManager의 0.1초 주기 틱과 항상 겹쳐 초당 횟수가 설정값과 정확히 같다.
    int tickrate = RoundToNearest(1.0 / GetTickInterval());
    int rate     = g_hUpdateRate.IntValue;
    int tick     = GetGameTickCount();
    if ((tick % tickrate) * rate / tickrate == ((tick - 1) % tickrate) * rate / tickrate)
    {
        return;
    }

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
