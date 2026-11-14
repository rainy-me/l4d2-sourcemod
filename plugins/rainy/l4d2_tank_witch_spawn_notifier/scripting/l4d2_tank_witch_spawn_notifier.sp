#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

#define WARN_SOUND "ui/pickup_secret01.wav"

ConVar g_hConVarSoundCooldownTime;
ConVar g_hConVarSoundVolume;
float  g_fTankSoundAllowTime  = 0.0;
float  g_fWitchSoundAllowTime = 0.0;

public Plugin myinfo =
{
    name        = "L4D2 Tank Witch Spawn Notifier",
    author      = "Rainy",
    description = "탱크 및 윗치의 스폰을 알립니다.",
    version     = "1.1.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_tank_witch_spawn_notifier"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_tank_witch_spawn_notifier.phrases");

    g_hConVarSoundCooldownTime = CreateConVar(
        "l4d2_tank_witch_spawn_notifier_sound_cooldown_time", "1.0",
        "Cooldown time between sound notifications. (in seconds)",
        FCVAR_NOTIFY, true, 0.0);
    g_hConVarSoundVolume = CreateConVar(
        "l4d2_tank_witch_spawn_notifier_sound_volume", "1.0",
        "Sound notification volume.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_tank_witch_spawn_notifier");

    HookEvent("round_start", Event_RoundStart);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("witch_spawn", Event_WitchSpawn);
}

public void OnMapStart()
{
    PrecacheSound(WARN_SOUND);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_fTankSoundAllowTime  = 0.0;
    g_fWitchSoundAllowTime = 0.0;
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    float currentTime = GetGameTime();
    if (currentTime > g_fTankSoundAllowTime)
    {
        EmitSoundToAll(WARN_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NONE, SND_NOFLAGS, g_hConVarSoundVolume.FloatValue);
        g_fTankSoundAllowTime = currentTime + g_hConVarSoundCooldownTime.FloatValue;
    }
    CPrintToChatAll("%t", "Tank Spawned");
}

void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast)
{
    float currentTime = GetGameTime();
    if (currentTime > g_fWitchSoundAllowTime)
    {
        EmitSoundToAll(WARN_SOUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NONE, SND_NOFLAGS, g_hConVarSoundVolume.FloatValue);
        g_fWitchSoundAllowTime = currentTime + g_hConVarSoundCooldownTime.FloatValue;
    }
    CPrintToChatAll("%t", "Witch Spawned");
}
