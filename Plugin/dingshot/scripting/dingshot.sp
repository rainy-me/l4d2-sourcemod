#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name        = "Dingshot",
    author      = "Rainy",
    description = "헤드샷 시 띵 소리를 출력합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/dingshot"
};

char g_sHeadshotSound[64] = "level/bell_normal.wav";

public void OnPluginStart()
{
    PrecacheSound(g_sHeadshotSound, false);
    HookEvent("player_hurt", HeadShotHook, EventHookMode_Pre);
    HookEvent("infected_hurt", HeadShotHook, EventHookMode_Pre);
}

void HeadShotHook(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int hitgroup = event.GetInt("hitgroup");
    int type     = event.GetInt("type");

    if (IsClientValid(attacker) && hitgroup == 1 && type != 8 && type != 2097152)
    {
        // 8 == death by fire
        // 2097152 == death by slow burn
        EmitSoundToClient(attacker, g_sHeadshotSound);
    }
}

bool IsClientValid(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
