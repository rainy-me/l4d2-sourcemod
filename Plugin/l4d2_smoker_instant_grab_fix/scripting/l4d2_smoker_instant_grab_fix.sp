#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Smoker Instant Grab Fix",
    author      = "Rainy",
    description = "스모커가 월드스폰이 아닌 엔티티 위에 서 있는 생존자를 잡을 때 즉시 끌려가는 버그를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_smoker_instant_grab_fix"
};

public void OnPluginStart()
{
    HookEvent("tongue_grab", Event_TongueGrab);
}

public void Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
    int smoker = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (!IsValidClient(smoker) || !IsValidClient(victim))
    {
        return;
    }

    // 방법 1: tongueVictimLastOnGroundTime을 현재 시간으로 리셋
    int ability = GetEntPropEnt(smoker, Prop_Send, "m_customAbility");
    if (IsValidEntity(ability) && HasEntProp(ability, Prop_Send, "m_tongueVictimLastOnGroundTime"))
    {
        SetEntPropFloat(ability, Prop_Send, "m_tongueVictimLastOnGroundTime", GetGameTime());
    }

    // 방법 2
    // 스모커가 생존자보다 높은 위치에 있는지 확인
    float smokerPos[3], victimPos[3];
    GetClientAbsOrigin(smoker, smokerPos);
    GetClientAbsOrigin(victim, victimPos);
    if (smokerPos[2] <= victimPos[2])
    {
        return;
    }

    // 생존자가 서 있는 지면이 월드스폰이 아닌지 확인
    int groundEnt = GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity");
    if (!IsValidEntity(groundEnt))
    {
        return;
    }
    char classname[64];
    GetEntityClassname(groundEnt, classname, sizeof(classname));
    if (StrEqual(classname, "worldspawn"))
    {
        return;
    }

    // 지면에서 분리 + 위로 살짝 밀어내기
    SetEntPropEnt(victim, Prop_Send, "m_hGroundEntity", -1);
    victimPos[2] += 20.0;
    TeleportEntity(victim, victimPos, NULL_VECTOR, NULL_VECTOR);

    float curVel[3];
    GetEntPropVector(victim, Prop_Data, "m_vecAbsVelocity", curVel);
    curVel[2] += 30.0;
    TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, curVel);
}

bool IsValidClient(int index)
{
    return index > 0 && index <= MaxClients && IsClientInGame(index);
}
