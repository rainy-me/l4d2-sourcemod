#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

enum
{
    STAGE_IDLE,        // 감시 안 함
    STAGE_WATCH,       // 스태거 진행 감시 중
    STAGE_CANCELLED    // 스태거 중 공중에 떠 타이머가 끊김 (낙하 취소)
};

int    g_iStage[MAXPLAYERS + 1];
int    g_iSource[MAXPLAYERS + 1];      // 스태거 방향 기준 (공격자)
float  g_fDeadline[MAXPLAYERS + 1];    // 이 시각이 지나면 재스태거 포기
ConVar g_cvMaxStagger;
int    g_iImpactCharger;    // 이번 틱에 벽에 충돌한 차저
int    g_iImpactTick;

public Plugin myinfo =
{
    name        = "L4D2 No SI Fall Stagger Cancel",
    author      = "Rainy",
    description = "특수좀비가 낙하로 스태거를 취소하지 못하도록 착지 시 다시 스태거를 겁니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_si_fall_stagger_cancel"
};

public void OnPluginStart()
{
    g_cvMaxStagger = FindConVar("z_max_stagger_duration");
    if (g_cvMaxStagger == null)
    {
        SetFailState("ConVar z_max_stagger_duration not found.");
    }
}

public void OnClientPutInServer(int client)
{
    g_iStage[client]  = STAGE_IDLE;
    g_iSource[client] = 0;
}

public void OnClientDisconnect(int client)
{
    g_iStage[client]  = STAGE_IDLE;
    g_iSource[client] = 0;
}

// 스태거 방향 기준점 기록
public void L4D_OnShovedBySurvivor_Post(int client, int victim, const float vecDir[3])
{
    if (IsClient(victim))
    {
        g_iSource[victim] = client;
    }
}

// 차저 충돌 스태거는 아래 OnStagger_Post에 source가 -1로 오므로, 같은 틱의 차저를 기억해 둔다.
public void L4D2_OnChargerImpact(int client)
{
    g_iImpactCharger = client;
    g_iImpactTick    = GetGameTickCount();
}

public void L4D2_OnStagger_Post(int client, int source)
{
    // 부머 폭발은 부머, 파이프·프로판은 던지거나 쏜 생존자, 차저 충돌은 -1로 온다.
    if (IsClient(source))
    {
        g_iSource[client] = source;
    }
    else if (source == -1 && g_iImpactTick == GetGameTickCount())
    {
        g_iSource[client] = g_iImpactCharger;    // 주변 SI는 차저 기준. 차저 본인은 자기 자신 기준(고정 방향)
    }
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
    if (GetClientTeam(client) != 3 || !IsPlayerAlive(client))
    {
        g_iStage[client]  = STAGE_IDLE;
        g_iSource[client] = 0;
        return Plugin_Continue;
    }

    bool bStaggering = GetEntPropFloat(client, Prop_Send, "m_staggerTimer", 1) > -1.0;
    bool bOnGround   = (GetEntityFlags(client) & FL_ONGROUND) != 0;

    switch (g_iStage[client])
    {
        case STAGE_IDLE:
        {
            if (bStaggering)
            {
                g_iStage[client]    = STAGE_WATCH;
                g_fDeadline[client] = GetGameTime() + g_cvMaxStagger.FloatValue;
            }
        }
        case STAGE_WATCH:
        {
            if (!bStaggering)
            {
                g_iStage[client] = bOnGround ? STAGE_IDLE : STAGE_CANCELLED;
                if (bOnGround)
                {
                    g_iSource[client] = 0;    // 스태거 정상 종료. 오래된 기준점이 다음 스태거에 쓰이지 않도록 초기화
                }
            }
        }
        case STAGE_CANCELLED:
        {
            if (bStaggering)
            {
                g_iStage[client] = STAGE_WATCH;
            }
            else if (GetGameTime() > g_fDeadline[client])
            {
                g_iStage[client]  = STAGE_IDLE;
                g_iSource[client] = 0;
            }
            else if (bOnGround)
            {
                ReStagger(client);
                g_iStage[client] = STAGE_WATCH;
            }
        }
    }

    return Plugin_Continue;
}

void ReStagger(int client)
{
    int source = g_iSource[client];
    if (!IsClient(source) || !IsClientInGame(source))
    {
        source = GetClosestSurvivor(client);
    }
    // 살아있는 생존자가 없음
    if (source <= 0)
    {
        return;
    }
    L4D_StaggerPlayer(client, source, NULL_VECTOR);
}

int GetClosestSurvivor(int client)
{
    float vOrigin[3], vPos[3];
    GetClientAbsOrigin(client, vOrigin);

    int   best     = 0;
    float bestDist = 0.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2 || !IsPlayerAlive(i))
        {
            continue;
        }
        GetClientAbsOrigin(i, vPos);
        float dist = GetVectorDistance(vOrigin, vPos, true);
        if (best == 0 || dist < bestDist)
        {
            best     = i;
            bestDist = dist;
        }
    }
    return best;
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
