#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define HEADSHOT_SOUND "level/bell_normal.wav"
#define VOLUME         0.85

ConVar g_hEnabled;

public Plugin myinfo =
{
    name        = "L4D2 Dingshot",
    author      = "Rainy",
    description = "헤드샷 시 띵 소리를 출력합니다.",
    version     = "1.1.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/archive/l4d2_dingshot"
};

public void OnPluginStart()
{
    g_hEnabled = CreateConVar(
        "dingshot_enabled", "1",
        "0=OFF, 1=ON",
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

// 프리캐시 목록은 맵마다 초기화된다
public void OnMapStart()
{
    PrecacheSound(HEADSHOT_SOUND);
}

void EnableDingshot()
{
    HookEvent("player_hurt", HeadshotHook, EventHookMode_Pre);
    HookEvent("infected_hurt", HeadshotHook, EventHookMode_Pre);
}

void DisableDingshot()
{
    UnhookEvent("player_hurt", HeadshotHook, EventHookMode_Pre);
    UnhookEvent("infected_hurt", HeadshotHook, EventHookMode_Pre);
}

void HeadshotHook(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int hitgroup = event.GetInt("hitgroup");
    int type     = event.GetInt("type");

    if (IsValidAliveClient(attacker) && hitgroup == 1 && !(type & DMG_BURN) && type != 2097152)
    {
        // DMG_BURN(8) == death by fire (다른 비트가 섞여도 제외)
        // 2097152 == death by slow burn
        EmitSoundToClient(attacker, HEADSHOT_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO,
                          SNDLEVEL_NONE, SND_NOFLAGS, VOLUME);
    }
}

bool IsValidAliveClient(int client)
{
    return (IsClient(client) && IsClientInGame(client) && IsPlayerAlive(client));
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
