#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

bool g_bEnabled = true;

public Plugin myinfo =
{
    name        = "One Punch Shove",
    author      = "Rainy",
    description = "CI, SI를 밀치기 한 번으로 죽일 수 있습니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Archive/l4d2_one_punch_shove"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_ops", Cmd_OnePunchShove, ADMFLAG_ROOT, "On/Off One-Punch Shove");
    HookEvent("player_shoved", Event_PlayerShoved);
    HookEvent("entity_shoved", Event_EntityShoved);
}

public void OnMapStart()
{
    MeleeRagdollEffect(g_bEnabled);
}

void MeleeRagdollEffect(bool enabled)
{
    if (enabled)
    {
        FindConVar("melee_force_scalar").IntValue                  = 7500;
        FindConVar("melee_force_scalar_combat_character").IntValue = 7500;
        FindConVar("z_push_force").IntValue                        = 10000;
        FindConVar("z_push_mass_max").IntValue                     = 20000;
        FindConVar("z_pushaway_force").IntValue                    = 1000;
    }
    else
    {
        FindConVar("melee_force_scalar").IntValue                  = 20;
        FindConVar("melee_force_scalar_combat_character").IntValue = 5;
        FindConVar("z_push_force").IntValue                        = 2000;
        FindConVar("z_push_mass_max").IntValue                     = 200;
        FindConVar("z_pushaway_force").IntValue                    = 100;
    }
}

Action Cmd_OnePunchShove(int client, int args)
{
    if (!IsClient(client) || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    g_bEnabled = !g_bEnabled;
    MeleeRagdollEffect(g_bEnabled);
    PrintToChatAll("\x01[One-Punch Shove] \x04%s", g_bEnabled ? "ON" : "OFF");
    return Plugin_Handled;
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (!g_bEnabled || !IsClient(client) || !IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
    {
        return;
    }
    if (!IsClient(victim) || !IsClientInGame(victim) || GetClientTeam(victim) != 3 || !IsPlayerAlive(victim))
    {
        return;
    }

    // One punch kill for SI
    // Apply damage twice for the tank ragdoll effect.
    SDKHooks_TakeDamage(victim, client, client, 100000.0, DMG_CLUB);
    SDKHooks_TakeDamage(victim, client, client, 100000.0, DMG_CLUB);
}

void Event_EntityShoved(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("attacker"));
    int entity = event.GetInt("entityid");

    if (!g_bEnabled || !IsClient(client) || !IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
    {
        return;
    }
    if (!IsValidEntity(entity))
    {
        return;
    }

    // One punch kill for CI and Witch
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
    {
        SDKHooks_TakeDamage(entity, client, client, 100000.0, DMG_CLUB);
    }
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
