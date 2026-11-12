#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

ConVar    g_hGravity;
ArrayList g_hProjectiles;

float     g_fResumeTime[2049];
float     g_vecResumePos[2049][3];
float     g_vecResumeVel[2049][3];
MoveType  g_iMoveType[2049];

public Plugin myinfo =
{
    name        = "L4D2 Grenade Sky Return",
    author      = "Rainy",
    description = "유탄이 하늘에 닿아 사라지지 않고, 하늘이 끝없이 열려 있는 것처럼 다시 떨어지게 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/archive/l4d2_grenade_sky_return"
};

public void OnPluginStart()
{
    g_hGravity     = FindConVar("sv_gravity");
    g_hProjectiles = new ArrayList();

    // Late load
    int entity     = -1;
    while ((entity = FindEntityByClassname(entity, "grenade_launcher_projectile")) != -1)
        Track(entity);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "grenade_launcher_projectile"))
        Track(entity);
}

void Track(int entity)
{
    g_fResumeTime[entity] = 0.0;
    g_hProjectiles.Push(EntIndexToEntRef(entity));
}

public void OnGameFrame()
{
    float now = GetGameTime();
    for (int i = g_hProjectiles.Length - 1; i >= 0; i--)
    {
        int entity = EntRefToEntIndex(g_hProjectiles.Get(i));
        if (entity == INVALID_ENT_REFERENCE)
            g_hProjectiles.Erase(i);
        else if (g_fResumeTime[entity] == 0.0)
            CheckSky(entity);
        else if (now >= g_fResumeTime[entity])
            Resume(entity);
    }
}

void CheckSky(int entity)
{
    float pos[3], vel[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
    if (vel[2] <= 0.0)
        return;

    float gravity = GetEntityGravity(entity);
    gravity       = (gravity == 0.0 ? 1.0 : gravity) * g_hGravity.FloatValue;
    if (gravity <= 0.0)
        return;

    float mins[3], maxs[3], end[3];
    GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);

    // 엔진은 하늘에 닿은 투사체를 터뜨리지 않고 지우므로 닿기 2틱 전에 가로챈다
    float lookahead = GetTickInterval() * 2.0;
    for (int i = 0; i < 3; i++)
        end[i] = pos[i] + vel[i] * lookahead;

    TR_TraceHullFilter(pos, end, mins, maxs, MASK_SOLID, Filter_Self, entity);
    if (!TR_DidHit() || !(TR_GetSurfaceFlags() & SURF_SKY))
        return;

    // 맵 가장자리의 하늘 벽은 원래대로 사라지게 두고, 아래를 향한 하늘 천장만 가로챈다
    float normal[3];
    TR_GetPlaneNormal(null, normal);
    if (normal[2] > -0.7)
        return;

    // 하늘이 없다면 정점을 찍고 이 높이로 돌아오기까지 걸리는 시간
    float hideTime = 2.0 * vel[2] / gravity;

    // 숨어 있는 동안의 수평 이동, 벽에 막히면 그 앞에서 떨어진다
    end[0]         = pos[0] + vel[0] * hideTime;
    end[1]         = pos[1] + vel[1] * hideTime;
    end[2]         = pos[2];
    TR_TraceHullFilter(pos, end, mins, maxs, MASK_SOLID, Filter_Self, entity);
    TR_GetEndPosition(g_vecResumePos[entity]);

    g_vecResumeVel[entity][0] = vel[0];
    g_vecResumeVel[entity][1] = vel[1];
    g_vecResumeVel[entity][2] = -vel[2];
    g_iMoveType[entity]       = GetEntityMoveType(entity);
    g_fResumeTime[entity]     = GetGameTime() + hideTime;

    TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 0.0 }));
    SetEntityMoveType(entity, MOVETYPE_NONE);

    // 클라이언트가 연기 꼬리를 다시 만들어 내므로 전송을 끊어 엔티티째로 휴면시킨다
    SDKHook(entity, SDKHook_SetTransmit, SetTransmit_Hidden);
}

void Resume(int entity)
{
    g_fResumeTime[entity] = 0.0;

    float ang[3];
    GetVectorAngles(g_vecResumeVel[entity], ang);

    SetEntityMoveType(entity, g_iMoveType[entity]);
    TeleportEntity(entity, g_vecResumePos[entity], ang, g_vecResumeVel[entity]);

    SDKUnhook(entity, SDKHook_SetTransmit, SetTransmit_Hidden);

    // 휴면이 풀린 꼬리는 밀린 연기를 한 점에 몰아 뿜으므로 끄고, 클라이언트가 새 꼬리를 만들게 한다
    // 숨길 때 끄면 이미 뿜어진 연기까지 즉시 지워져서 여기서 끈다
    StopParticles(entity);
}

Action SetTransmit_Hidden(int entity, int client)
{
    return Plugin_Handled;
}

void StopParticles(int entity)
{
    TE_Start("EffectDispatch");
    TE_WriteFloat("m_vOrigin.x", 0.0);
    TE_WriteFloat("m_vOrigin.y", 0.0);
    TE_WriteFloat("m_vOrigin.z", 0.0);
    TE_WriteFloat("m_vStart.x", 0.0);
    TE_WriteFloat("m_vStart.y", 0.0);
    TE_WriteFloat("m_vStart.z", 0.0);
    TE_WriteVector("m_vAngles", view_as<float>({ 0.0, 0.0, 0.0 }));
    TE_WriteNum("m_iEffectName", FindStringIndex(FindStringTable("EffectDispatch"), "ParticleEffectStop"));
    TE_WriteNum("m_nHitBox", 0);
    TE_WriteNum("entindex", entity);
    TE_WriteNum("m_nAttachmentIndex", 0);
    TE_WriteNum("m_fFlags", 1);
    TE_WriteFloat("m_flMagnitude", 0.0);
    TE_WriteFloat("m_flScale", 0.0);
    TE_WriteFloat("m_flRadius", 0.0);
    TE_WriteNum("m_nDamageType", 0);
    TE_SendToAll();
}

bool Filter_Self(int entity, int contentsMask, int self)
{
    return entity != self;
}
