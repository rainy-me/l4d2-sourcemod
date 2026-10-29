#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define DMG_STUMBLE   (1 << 25)
#define SHOVE_RANGE   120.0
#define SHOVE_COS     0.642788    // cos(50°)
#define ZC_CHARGER    6
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

ConVar g_cvSwingInterval;

public Plugin myinfo =
{
    name        = "L4D2 Smoker Melee Shove",
    author      = "Rainy",
    description = "스모커 혀에 끌려가는 동안 근접무기로 밀치기를 할 수 있도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_smoker_melee_shove"
};

public void OnPluginStart()
{
    g_cvSwingInterval = FindConVar("z_gun_swing_interval");
}

public void OnPlayerRunCmdPost(int client)
{
    // 이번 틱에 막 누른 버튼만 본다
    if (!(GetEntProp(client, Prop_Data, "m_afButtonPressed") & IN_ATTACK2))
        return;

    if (IsFakeClient(client) || !IsBeingPulled(client))
        return;

    int  weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    char cls[16];
    if (weapon == -1 || !GetEntityClassname(weapon, cls, sizeof(cls)) || !StrEqual(cls, "weapon_melee"))
        return;

    float now = GetGameTime();
    if (now < GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack")
        || now < GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack"))
        return;

    SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", now + g_cvSwingInterval.FloatValue);
    PlayShoveAnimation(client);
    EmitGameSoundToAll("Weapon.Swing", client);

    if (!StaggerNearby(client))
        CreateTimer(0.1, Timer_Retry, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

/** 혀에 잡혀 공중으로 당겨지는 중 (목 조르기 전, 바닥 끌림 전) */
bool IsBeingPulled(int client)
{
    if (!IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVOR)
        return false;

    if (GetEntProp(client, Prop_Send, "m_isIncapacitated") || GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
        return false;

    if (L4D_GetAttackerSmoker(client) == 0 || L4D_HasReachedSmoker(client))
        return false;

    int act = PlayerAnimState.FromPlayer(client).GetMainActivity();
    return act < L4D2_ACT_TERROR_DRAGGING_FROM_TONGUE || act > L4D2_ACT_TERROR_DRAGGING_FROM_TONGUE_FEMALE;
}

Action Timer_Retry(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsBeingPulled(client))
        StaggerNearby(client);
    return Plugin_Stop;
}

bool StaggerNearby(int client)
{
    float origin[3], pos[3];
    GetClientAbsOrigin(client, origin);
    bool hit = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_INFECTED || !IsPlayerAlive(i))
            continue;
        if (GetEntProp(i, Prop_Send, "m_isGhost") || GetEntProp(i, Prop_Send, "m_zombieClass") >= ZC_CHARGER)
            continue;

        GetClientAbsOrigin(i, pos);
        if (!CanShove(client, origin, pos))
            continue;

        L4D_StaggerPlayer(i, client, origin);
        hit = true;
    }

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "infected")) != -1)
    {
        if (GetEntProp(ent, Prop_Data, "m_lifeState") != 0)
            continue;

        GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", pos);
        if (!CanShove(client, origin, pos))
            continue;

        SDKHooks_TakeDamage(ent, client, client, 1.0, DMG_STUMBLE);
        hit = true;
    }

    if (hit)
        EmitGameSoundToAll("Weapon.HitInfected", client);

    return hit;
}

/** 사거리 안, 정면 50° 원뿔 안에 있고 월드에 가려지지 않았는지 */
bool CanShove(int client, const float origin[3], const float targetOrigin[3])
{
    if (GetVectorDistance(origin, targetOrigin) > SHOVE_RANGE)
        return false;

    float eye[3], ang[3], fwd[3], end[3], dir[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, ang);
    GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

    end = targetOrigin;
    end[2] += 30.0;

    MakeVectorFromPoints(eye, end, dir);
    float len = GetVectorLength(dir);
    if (len <= 0.0 || GetVectorDotProduct(fwd, dir) / len < SHOVE_COS)
        return false;

    TR_TraceRayFilter(eye, end, MASK_NPCWORLDSTATIC, RayType_EndPoint, TraceFilter_IgnoreSelf, client);
    return TR_GetFraction() >= 0.999;
}

bool TraceFilter_IgnoreSelf(int entity, int contentsMask, any data)
{
    return entity != data;
}

/**
 * 3인칭은 게임의 밀치기 애니메이션 이벤트를 그대로 쓴다.
 * 1인칭 뷰모델은 LookupSequence 가 필요해 생존자 엔티티에 VScript 로 보낸다.
 */
void PlayShoveAnimation(int client)
{
    L4D2Direct_DoAnimationEvent(client, PLAYERANIMEVENT_SHOVE);
    SetVariantString(
        "local w=self.GetActiveWeapon();"
    ... "local vm=NetProps.GetPropEntity(self,\"m_hViewModel\");"
    ... "local t=Time();"
    ... "local s=w.LookupSequence(\"ACT_VM_SECONDARYATTACK\");"
    ... "NetProps.SetPropIntArray(w,\"m_NetGestureSequence\",s,5);"
    ... "NetProps.SetPropIntArray(w,\"m_NetGestureActivity\",w.LookupActivity(\"ACT_VM_SECONDARYATTACK\"),5);"
    ... "NetProps.SetPropFloatArray(w,\"m_NetGestureStartTime\",0,5);"
    ... "if(vm){"
    ...     "NetProps.SetPropInt(vm,\"m_nLayerSequence\",s);"
    ...     "NetProps.SetPropInt(vm,\"m_nLayer\",0);"
    ...     "NetProps.SetPropFloat(vm,\"m_flLayerStartTime\",t);"
    ... "}"
    // 도움의 손길 모션이 끼어들지 않도록 잠시 억제
    ... "NetProps.SetPropFloat(w,\"m_helpingHandSuppressionTimer.m_duration\",1);"
    ... "NetProps.SetPropFloat(w,\"m_helpingHandSuppressionTimer.m_timestamp\",t+1);"
    ... "NetProps.SetPropInt(w,\"m_helpingHandState\",0);"
    );
    AcceptEntityInput(client, "RunScriptCode");
}
