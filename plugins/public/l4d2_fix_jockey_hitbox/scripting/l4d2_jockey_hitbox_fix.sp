#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define PLUGIN_VERSION "2.3"

public Plugin myinfo =
{
    name        = "[L4D2] Fix Jockey Hitbox",
    author      = "Forgetest",
    description = "Fix jockey hitbox issues when riding survivors.",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

// source-sdk: src/game/server/nav.h
#define HumanHeight 71

int g_iOffs_m_flEstIkOffset;

public void OnPluginStart()
{
    g_iOffs_m_flEstIkOffset = FindSendPropInfo("CBaseAnimating", "m_flModelScale") + 24;

    HookEvent("jockey_ride_end", Event_JockeyRideEnd);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

// Hooked for the client's whole lifetime: m_jockeyAttacker may not be set yet
// when jockey_ride / bot replace events fire, so event-time checks miss rides.
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PostThink, SDK_OnPostThink);
}

void SDK_OnPostThink(int client)
{
    if (GetClientTeam(client) != 2)
        return;

    int attacker = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
    if (attacker == -1)
        return;

    // Fix bounding box
    int flags = GetEntityFlags(client);
    if (flags & FL_DUCKING)
    {
        SetEntityFlags(client, flags & ~FL_DUCKING);
    }

    // https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/game/server/baseanimating.cpp#L1800
    /**
     *   // adjust hit boxes based on IK driven offset
     *   Vector adjOrigin = GetAbsOrigin() + Vector( 0, 0, m_flEstIkOffset );
     */
    int   character = GetEntProp(client, Prop_Send, "m_survivorCharacter");

    float flOffset  = HumanHeight * (GetCharacterScale(character) - 1.0);
    if (flOffset != GetEntDataFloat(attacker, g_iOffs_m_flEstIkOffset))
    {
        SetEntDataFloat(attacker, g_iOffs_m_flEstIkOffset, flOffset);
    }
}

void Event_JockeyRideEnd(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    if (!attacker || !IsClientInGame(attacker))
        return;

    SetEntDataFloat(attacker, g_iOffs_m_flEstIkOffset, 0.0);
}

float GetCharacterScale(int survivorCharacter)
{
    static const float k_flScales[] = {
        1.0,      // Nick
        0.888,    // Rochelle
        1.05,     // Coach
        0.955,    // Ellis
        1.0,      // Bill
        0.888,    // Zoey
        1.0,      // Francis
        1.0,      // Louis

        1.0,    // Unknown
    };

    return k_flScales[ConvertToExternalCharacter(survivorCharacter)];
}

int ConvertToExternalCharacter(int survivorCharacter)
{
    if (survivorCharacter < 0 || survivorCharacter > 7)
        return 8;

    if (L4D2_GetSurvivorSetMod() == 1)
        return survivorCharacter < 4 ? survivorCharacter + 4 : 8;

    return survivorCharacter;
}