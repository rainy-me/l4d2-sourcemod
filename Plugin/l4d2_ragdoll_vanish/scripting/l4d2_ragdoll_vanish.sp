#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Ragdoll Vanish",
    author      = "Rainy",
    description = "CI/SI의 ragdoll을 즉시 제거합니다.",
    version     = "1.0.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_ragdoll_vanish"
};

public void OnPluginStart()
{
    HookEvent("player_death", Event_PlayerDeath);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // Remove Smoker, Boomer, Hunter, Spitter, Jockey, Charger, Tank ragdolls
    if (StrEqual(classname, "cs_ragdoll"))
    {
        RequestFrame(Frame_RemoveEntity, entity);
    }
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("entityid");
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        return;
    }

    // Remove CI, Witch ragdolls
    static char sClassName[64];
    GetEntityClassname(entity, sClassName, sizeof(sClassName));
    if (StrEqual(sClassName, "infected") || StrEqual(sClassName, "witch"))
    {
        RequestFrame(Frame_RemoveEntity, entity);
    }
}

void Frame_RemoveEntity(int entity)
{
    RemoveEntity(entity);
}
