#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define DMG_MELEE 2097152

public Plugin myinfo =
{
    name        = "L4D2 No CI Melee Kill Collision",
    author      = "Rainy",
    description = "근접무기로 죽인 일반좀비와의 충돌을 제거합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_no_ci_melee_kill_collision"
};

public void OnPluginStart()
{
    HookEvent("player_death", Event_PlayerDeath);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    if (userid > 0)
    {
        return;
    }
    int entity = event.GetInt("entityid");
    if (entity < MaxClients || !IsValidEntity(entity))
    {
        return;
    }
    char victimName[32];
    event.GetString("victimname", victimName, sizeof(victimName));
    if (!StrEqual(victimName, "Infected"))
    {
        return;
    }
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    if (!StrEqual(weapon, "melee"))
    {
        return;
    }
    int damageType = event.GetInt("type");
    if (!(damageType & DMG_MELEE))
    {
        return;
    }

    SetEntProp(entity, Prop_Send, "m_CollisionGroup", 1);
}