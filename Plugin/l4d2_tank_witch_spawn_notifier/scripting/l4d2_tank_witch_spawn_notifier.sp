#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

#define WARN_SOUND "ui/pickup_secret01.wav"

ConVar g_hSoundCooldownTime;
ConVar g_hSoundVolume;
float  g_fTankSoundAllowTime  = 0.0;
float  g_fWitchSoundAllowTime = 0.0;

public Plugin myinfo =
{
    name        = "L4D2 Tank Witch Spawn Notifier",
    author      = "Rainy",
    description = "탱크 및 윗치의 스폰을 알립니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_tank_witch_spawn_notifier"
};

public void OnPluginStart()
{
    g_hSoundCooldownTime = CreateConVar("l4d2_tank_witch_spawn_notifier_sound_cooldown_time", "1.0",
                                        "Cooldown time between sound notifications. (in seconds)",
                                        FCVAR_NOTIFY, true, 0.0);
    g_hSoundVolume       = CreateConVar("l4d2_tank_witch_spawn_notifier_sound_volume", "1.0",
                                        "Sound notification volume.",
                                        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_tank_witch_spawn_notifier");

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("witch_spawn", Event_WitchSpawn);
    // HookEvent("player_death", Event_PlayerDeath);
}

public void OnMapStart()
{
    PrecacheSound(WARN_SOUND);
    g_fTankSoundAllowTime  = 0.0;
    g_fWitchSoundAllowTime = 0.0;
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    float currentTime = GetGameTime();
    if (currentTime > g_fTankSoundAllowTime)
    {
        EmitSoundToAll(WARN_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NONE, SND_NOFLAGS, g_hSoundVolume.FloatValue);
        g_fTankSoundAllowTime = currentTime + g_hSoundCooldownTime.FloatValue;
    }
    CPrintToChatAll("{green}[{lightgreen}!{green}]{olive} Tank {green}has spawned!");
}

void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast)
{
    float currentTime = GetGameTime();
    if (currentTime > g_fWitchSoundAllowTime)
    {
        EmitSoundToAll(WARN_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NONE, SND_NOFLAGS, g_hSoundVolume.FloatValue);
        g_fWitchSoundAllowTime = currentTime + g_hSoundCooldownTime.FloatValue;
    }
    CPrintToChatAll("{green}[{lightgreen}!{green}]{olive} Witch {green}has spawned!");
}

// void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
// {
//     int client = GetClientOfUserId(event.GetInt("userid"));
//     if (!IsValidTank(client))
//     {
//         return;
//     }

//     if (GetEntProp(client, Prop_Send, "m_zombieClass") == 8)
//     {
//         CPrintToChatAll("{green}[{lightgreen}!{green}]{olive} Tank {green}has been killed!");
//     }
// }

// bool IsValidTank(int client)
// {
//     return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetEntProp(client, Prop_Send, "m_zombieClass") == 8);
// }