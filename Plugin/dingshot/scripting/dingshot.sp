#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define VOLUME 0.85

public Plugin myinfo =
{
    name        = "Dingshot",
    author      = "Rainy",
    description = "헤드샷 시 띵 소리를 출력합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/dingshot"
};

ConVar g_hEnabled;
char   g_sHeadshotSound[64] = "level/bell_normal.wav";

public void OnPluginStart()
{
    g_hEnabled = CreateConVar("dingshot_enabled", "1",
                              "0 = Plugin OFF, 1 = Plugin ON",
                              FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hEnabled.AddChangeHook(OnConVarChanged);
    AutoExecConfig(true, "dingshot");

    if (g_hEnabled.BoolValue)
    {
        EnableDingshot();
    }
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_hEnabled.BoolValue)
    {
        EnableDingshot();
    }
    else
    {
        DisableDingshot();
    }
}

void EnableDingshot()
{
    PrecacheSound(g_sHeadshotSound, false);
    HookEvent("player_hurt", HeadShotHook, EventHookMode_Pre);
    HookEvent("infected_hurt", HeadShotHook, EventHookMode_Pre);
}

void DisableDingshot()
{
    UnhookEvent("player_hurt", HeadShotHook, EventHookMode_Pre);
    UnhookEvent("infected_hurt", HeadShotHook, EventHookMode_Pre);
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
        EmitSoundToClient(attacker, g_sHeadshotSound, SOUND_FROM_PLAYER, SNDCHAN_AUTO,
                          SNDLEVEL_NORMAL, SND_NOFLAGS, VOLUME);
    }
}

bool IsClientValid(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
