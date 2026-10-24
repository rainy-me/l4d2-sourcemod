#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define GOAL_SPAWN_RANGE 128.0
#define COMMAND_INTERVAL 0.2
#define GENDER_WORKER    13
#define GOAL_CHASE_RANGE 4096.0

ArrayList g_hGoals;    // 담즙 폭탄이 만든 info_goal_infected_chase 엔티티 레퍼런스
Handle    g_hTimer;

public Plugin myinfo =
{
    name        = "L4D2 Worker Bile Fix",
    author      = "Rainy",
    description = "공사장 인부 좀비가 담즙 폭탄에 반응하도록 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_worker_bile_fix"
};

public void OnPluginStart()
{
    g_hGoals = new ArrayList();
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_hGoals.Clear();
    delete g_hTimer;
}

public void L4D2_VomitJar_Detonate_Post(int entity, int client)
{
    DataPack pack = new DataPack();
    float    vPos[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vPos);
    pack.WriteFloatArray(vPos, 3);
    // 추적 목표 엔티티는 폭발 처리 뒤에 생성되므로 한 프레임 미룬다
    RequestFrame(Frame_CollectGoals, pack);
}

void Frame_CollectGoals(DataPack pack)
{
    float vBile[3], vGoal[3];
    pack.Reset();
    pack.ReadFloatArray(vBile, 3);
    delete pack;

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "info_goal_infected_chase")) != -1)
    {
        GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vGoal);
        if (GetVectorDistance(vBile, vGoal) <= GOAL_SPAWN_RANGE)
        {
            g_hGoals.Push(EntIndexToEntRef(ent));
        }
    }

    if (g_hGoals.Length > 0 && g_hTimer == null)
    {
        g_hTimer = CreateTimer(COMMAND_INTERVAL, Timer_CommandWorkers, _, TIMER_REPEAT);
    }
}

Action Timer_CommandWorkers(Handle timer)
{
    for (int i = g_hGoals.Length - 1; i >= 0; i--)
    {
        if (EntRefToEntIndex(g_hGoals.Get(i)) == INVALID_ENT_REFERENCE)
        {
            g_hGoals.Erase(i);
        }
    }

    if (g_hGoals.Length == 0)
    {
        g_hTimer = null;
        return Plugin_Stop;
    }

    if (IsAnyoneBiled())
    {
        return Plugin_Continue;
    }

    float vGoal[3], vCommon[3];
    int   common = -1;
    while ((common = FindEntityByClassname(common, "infected")) != -1)
    {
        if (GetEntProp(common, Prop_Send, "m_Gender") != GENDER_WORKER)
        {
            continue;
        }

        GetEntPropVector(common, Prop_Data, "m_vecAbsOrigin", vCommon);
        for (int i = g_hGoals.Length - 1; i >= 0; i--)
        {
            int goal = EntRefToEntIndex(g_hGoals.Get(i));
            GetEntPropVector(goal, Prop_Data, "m_vecAbsOrigin", vGoal);
            if (GetVectorDistance(vCommon, vGoal) <= GOAL_CHASE_RANGE)
            {
                L4D2_CommandABot(common, goal, BOT_CMD_ATTACK);
                break;
            }
        }
    }
    return Plugin_Continue;
}

bool IsAnyoneBiled()
{
    float now = GetGameTime();
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetEntPropFloat(i, Prop_Send, "m_itTimer", 1) > now)
        {
            return true;
        }
    }
    return false;
}
