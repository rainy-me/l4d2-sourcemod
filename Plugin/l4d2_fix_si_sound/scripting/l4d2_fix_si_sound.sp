#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define TEAM_INFECTED 3

public Plugin myinfo =
{
    name        = "L4D2 Fix SI Sound",
    author      = "Rainy",
    description = "특수좀비의 소리 문제를 개선합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_fix_si_sound"
};

bool        g_bEmitJockeyIdleSound = false;
ConVar      g_hJockeyIdleSoundInterval;
Handle      g_hJockeySoundTimer[MAXPLAYERS + 1];
static char g_sJockeySound[][] = {
    "player/jockey/voice/idle/jockey_recognize02.wav",
    "player/jockey/voice/idle/jockey_recognize06.wav",
    "player/jockey/voice/idle/jockey_recognize07.wav",
    "player/jockey/voice/idle/jockey_recognize08.wav",
    "player/jockey/voice/idle/jockey_recognize09.wav",
    "player/jockey/voice/idle/jockey_recognize10.wav",
    "player/jockey/voice/idle/jockey_recognize11.wav",
    "player/jockey/voice/idle/jockey_recognize13.wav",
    "player/jockey/voice/idle/jockey_recognize15.wav",
    "player/jockey/voice/idle/jockey_recognize16.wav",
    "player/jockey/voice/idle/jockey_recognize17.wav",
    "player/jockey/voice/idle/jockey_recognize18.wav"
};

public void OnPluginStart()
{
    g_hJockeyIdleSoundInterval = CreateConVar("jockey_idle_sound_interval", "1.7",
                                              "Interval between jockey idle sounds.",
                                              FCVAR_NOTIFY, true, 0.0);
    AutoExecConfig(true, "l4d2_fix_si_sound");

    AddNormalSoundHook(SoundHook);
    HookEvent("player_spawn", PlayerSpawn_Event);
    HookEvent("player_death", PlayerDeath_Event);
    HookEvent("player_team", PlayerTeam_Event);
    HookEvent("jockey_ride", JockeyRideStart_Event);
    HookEvent("jockey_ride_end", JockeyRideEnd_Event);
}

public void OnMapStart()
{
    // Precache
    for (int i = 0; i < sizeof(g_sJockeySound); i++)
    {
        PrecacheSound(g_sJockeySound[i], true);
    }
    // avoid invalid timer handle exceptions after map transitions
    for (int i = 1; i <= MaxClients; i++)
    {
        g_hJockeySoundTimer[i] = null;
    }
}

Action SoundHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (!IsClient(entity) || !IsClientInGame(entity) || GetClientTeam(entity) != TEAM_INFECTED)
    {
        return Plugin_Continue;
    }

    // 자키가 생존자에게 올라타고 있지 않으면 공격 소리 막기 (불필요한 소리 호출 버그 해결)
    if (StrContains(sample, "player/jockey/voice/attack/jockey_attackloop", false) != -1 && L4D_GetVictimJockey(entity) == 0)
    {
        return Plugin_Stop;
    }

    int zClass = L4D2_GetPlayerZombieClass(entity);
    switch (zClass)
    {
        case L4D2ZombieClass_Smoker:
        {
            // 스모커 타겟 포착 소리 막기 (타겟 포착 소리 재생 때문에 warn 소리가 차단되는 문제 해결)
            if (StrContains(sample, "player/smoker/voice/idle/smoker_spotprey", false) != -1)
            {
                return Plugin_Stop;
            }
        }
        case L4D2ZombieClass_Jockey:
        {
            // 게임 엔진에서 재생하는 자키 idle 소리 막기 (플러그인에서 강제로 재생하는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/jockey/voice/idle/jockey_recognize", false) != -1 && !g_bEmitJockeyIdleSound)
            {
                return Plugin_Stop;
            }
        }
    }

    return Plugin_Continue;
}

public void L4D_OnEnterGhostState(int client)
{
    // Simply disable the timer if the client enters ghost mode and has the timer set.
    ChangeJockeyTimerStatus(client, false);
}

void PlayerSpawn_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    // Kill the sound timer if it exists (this will also trigger if you switch to Tank)
    ChangeJockeyTimerStatus(client, false);

    if (GetClientTeam(client) != TEAM_INFECTED)
    {
        return;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Jockey)
    {
        return;
    }

    // Setup the sound interval
    RequestFrame(JockeyRideEnd_NextFrame, GetClientUserId(client));
}

void PlayerDeath_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    // Kill the sound timer if it exists
    ChangeJockeyTimerStatus(client, false);
}

void PlayerTeam_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    // Kill the sound timer if it exists
    ChangeJockeyTimerStatus(client, false);
}

void JockeyRideStart_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    // Kill the sound timer if it exists
    ChangeJockeyTimerStatus(client, false);
}

void JockeyRideEnd_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    // Check if our beloved Jockey is alive on the very next frame
    RequestFrame(JockeyRideEnd_NextFrame, GetClientUserId(client));
}

void JockeyRideEnd_NextFrame(any userid)
{
    int client = GetClientOfUserId(userid);
    if (IsClient(client) && IsClientInGame(client) && IsPlayerAlive(client) && !GetEntProp(client, Prop_Send, "m_isGhost"))
    {
        // Resume our sound spam as the Jockey is still alive
        if (GetClientTeam(client) == TEAM_INFECTED && L4D2_GetPlayerZombieClass(client) == L4D2ZombieClass_Jockey)
        {
            ChangeJockeyTimerStatus(client, true);
        }
    }
}

Action EmitJockeyIdleSound(Handle timer, any client)
{
    int rndPick            = GetRandomInt(0, (sizeof(g_sJockeySound) - 1));
    g_bEmitJockeyIdleSound = true;
    EmitSoundToAll(g_sJockeySound[rndPick], client, SNDCHAN_VOICE, SNDLEVEL_HELICOPTER);
    g_bEmitJockeyIdleSound = false;

    return Plugin_Continue;
}

void ChangeJockeyTimerStatus(int client, bool bEnable)
{
    if (g_hJockeySoundTimer[client] != null)
    {
        delete g_hJockeySoundTimer[client];
    }

    if (bEnable)
    {
        g_hJockeySoundTimer[client] = CreateTimer(g_hJockeyIdleSoundInterval.FloatValue, EmitJockeyIdleSound, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}