#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define ZC_HUNTER      3
#define ZC_JOCKEY      5
#define ZC_TANK        8

// 스태거가 끝난 뒤 공격을 다시 허용하기까지의 지연
#define REENABLE_DELAY 0.5

// 클라이언트별 스태거/공중 상태 종료 시각. 0.0이면 쿨다운 아님
float g_fBlockEndTime[MAXPLAYERS + 1] = { 0.0, ... };

public Plugin myinfo =
{
    name        = "L4D2 AI Stagger Claw Fix",
    author      = "Rainy",
    description = "AI SI가 비틀거리거나 공중에 떠 있는 동안 긁기공격을 하지 못하도록 방지합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_ai_stagger_claw_fix"
};

public void OnClientDisconnect(int client)
{
    g_fBlockEndTime[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
    if (!IsFakeClient(client) || GetClientTeam(client) != 3 || !IsPlayerAlive(client))
        return Plugin_Continue;

    int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zombieClass == ZC_TANK)
        return Plugin_Continue;

    bool shouldBlock = false;

    // 조건 1: 스태거 중
    if (GetEntPropFloat(client, Prop_Send, "m_staggerTimer", 1) > -1.0)
        shouldBlock = true;
    // 조건 2: 헌터·자키가 공중에 떠 있음 (데드스톱 등)
    if (!shouldBlock && !(GetEntityFlags(client) & FL_ONGROUND) && (zombieClass == ZC_HUNTER || zombieClass == ZC_JOCKEY))
        shouldBlock = true;

    if (shouldBlock)
    {
        // 스태거/공중 상태인 동안 공격을 막고 종료 시각을 계속 갱신
        g_fBlockEndTime[client] = GetGameTime() + REENABLE_DELAY;
        buttons &= ~IN_ATTACK2;
        return Plugin_Changed;
    }

    // 스태거가 끝난 뒤 쿨다운 구간
    if (g_fBlockEndTime[client] > GetGameTime())
    {
        buttons &= ~IN_ATTACK2;
        return Plugin_Changed;
    }

    g_fBlockEndTime[client] = 0.0;
    return Plugin_Continue;
}
