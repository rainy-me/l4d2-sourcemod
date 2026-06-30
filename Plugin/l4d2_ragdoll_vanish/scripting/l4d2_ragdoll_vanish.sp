#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Ragdoll Vanish",
    author      = "Rainy",
    description = "CI/SI의 ragdoll을 즉시 제거합니다.",
    version     = "1.2.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_ragdoll_vanish"
};

public void OnPluginStart()
{
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    if (userid < 1)
    {
        // Remove CI ragdolls
        int entity = event.GetInt("entityid");
        if (entity > MaxClients && IsValidEntity(entity))
        {
            static char classname[64];
            GetEntityClassname(entity, classname, sizeof(classname));
            if (StrEqual(classname, "infected"))
            {
                RemoveEntity(entity);
            }
        }
    }
    else
    {
        // Remove SI ragdolls
        int client = GetClientOfUserId(userid);
        if (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 3)
        {
            int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
            if (ragdoll > MaxClients && IsValidEntity(ragdoll))
            {
                RemoveEntity(ragdoll);
            }
        }
    }
}
