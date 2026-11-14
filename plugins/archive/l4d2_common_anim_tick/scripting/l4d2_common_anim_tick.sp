#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define GAMEDATA "l4d2_common_anim_tick"

Handle    g_hStudioFrameAdvance;
ArrayList g_hCommons;

public Plugin myinfo =
{
    name        = "L4D2 Common Anim Tick",
    author      = "Rainy",
    description = "일반 좀비의 애니메이션을 매 틱 진행시켜 서버 히트박스의 자세가 NextBot 업데이트 주기만큼 늦는 문제를 수정합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/archive/l4d2_common_anim_tick"
};

public void OnPluginStart()
{
    GameData gameData = new GameData(GAMEDATA);
    if (gameData == null)
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);

    StartPrepSDKCall(SDKCall_Entity);
    if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Virtual, "CBaseAnimating::StudioFrameAdvance"))
        SetFailState("Failed to get offset 'CBaseAnimating::StudioFrameAdvance'.");
    g_hStudioFrameAdvance = EndPrepSDKCall();
    delete gameData;

    g_hCommons = new ArrayList();

    // Late load
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "infected")) != -1)
        g_hCommons.Push(entity);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (strcmp(classname, "infected") == 0)
        g_hCommons.Push(entity);
}

public void OnEntityDestroyed(int entity)
{
    int index = g_hCommons.FindValue(entity);
    if (index != -1)
        g_hCommons.Erase(index);
}

public void OnGameFrame()
{
    // 일반 좀비의 애니메이션은 ZombieBotBody::Update(NextBot 업데이트 주기)에서만 진행되어 그 사이 틱의 히트박스가 멈춰 있다.
    // 여기서는 cycle만 진행시킨다. 애니메이션 이벤트는 m_flLastEventCheck부터 처리되므로 원래 Update에서 지금과 같은 시점에 나간다.
    for (int i = 0; i < g_hCommons.Length; i++)
        SDKCall(g_hStudioFrameAdvance, g_hCommons.Get(i));
}
