#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define SMOKER_IDLE_INTERVAL  2.45
#define HUNTER_GROWL_INTERVAL 2.6    // 헌터는 idle 소리가 없고, 웅크리는 동안 growl을 낸다
#define JOCKEY_IDLE_INTERVAL  1.7
#define CHARGER_IDLE_INTERVAL 1.7
#define JOCKEY_CUE_RANGE      510.0    // 자키가 이 거리 안에서 생존자를 보면 idle 소리를 즉시 낸다

// 플러그인이 alert를 낸 뒤 이 시간 동안 엔진의 alert를 막는다 (가장 긴 alert가 약 3초)
#define ALERT_BLOCK_TIME      3.0

ConVar g_hConVarAutoConvars;

bool   g_bEmitting[MAXPLAYERS + 1];    // 플러그인이 직접 소리를 내는 중인지
bool   g_bIdleCue[MAXPLAYERS + 1];     // 지난 틱에 헌터가 웅크리고 있었는지, 자키가 생존자를 보고 있었는지
float  g_fAlertTime[MAXPLAYERS + 1];
float  g_fJockeyCueTime[MAXPLAYERS + 1];
Handle g_hIdleTimer[MAXPLAYERS + 1];

static char g_sSmokerAlert[][] = {
    "player/smoker/voice/alert/smoker_alert_01.wav",
    "player/smoker/voice/alert/smoker_alert_02.wav",
    "player/smoker/voice/alert/smoker_alert_03.wav",
    "player/smoker/voice/alert/smoker_alert_04.wav",
    "player/smoker/voice/alert/smoker_alert_05.wav",
    "player/smoker/voice/alert/smoker_alert_06.wav"
};
static char g_sHunterAlert[][] = {
    "player/hunter/voice/alert/hunter_alert_01.wav",
    "player/hunter/voice/alert/hunter_alert_02.wav",
    "player/hunter/voice/alert/hunter_alert_03.wav",
    "player/hunter/voice/alert/hunter_alert_04.wav",
    "player/hunter/voice/alert/hunter_alert_05.wav"
};
static char g_sJockeyAlert[][] = {
    "player/jockey/voice/alert/jockey_02.wav",
    "player/jockey/voice/alert/jockey_04.wav"
};
static char g_sChargerAlert[][] = {
    "player/charger/voice/alert/charger_alert_01.wav",
    "player/charger/voice/alert/charger_alert_02.wav"
};
static char g_sHunterGrowl[][] = {
    "player/hunter/voice/idle/hunter_stalk_04.wav",
    "player/hunter/voice/idle/hunter_stalk_05.wav",
    "player/hunter/voice/idle/hunter_stalk_06.wav",
    "player/hunter/voice/idle/hunter_stalk_07.wav",
    "player/hunter/voice/idle/hunter_stalk_08.wav",
    "player/hunter/voice/idle/hunter_stalk_09.wav"
};
static char g_sSmokerIdle[][] = {
    "player/smoker/voice/idle/smoker_lurk_01.wav",
    "player/smoker/voice/idle/smoker_lurk_03.wav",
    "player/smoker/voice/idle/smoker_lurk_04.wav",
    "player/smoker/voice/idle/smoker_lurk_06.wav",
    "player/smoker/voice/idle/smoker_lurk_08.wav",
    "player/smoker/voice/idle/smoker_lurk_10.wav",
    "player/smoker/voice/idle/smoker_lurk_11.wav",
    "player/smoker/voice/idle/smoker_lurk_12.wav",
    "player/smoker/voice/idle/smoker_lurk_13.wav"
};
static char g_sJockeyIdle[][] = {
    "player/jockey/voice/idle/jockey_recognize02.wav",
    "player/jockey/voice/idle/jockey_recognize06.wav",
    "player/jockey/voice/idle/jockey_recognize07.wav",
    "player/jockey/voice/idle/jockey_recognize08.wav",
    "player/jockey/voice/idle/jockey_recognize09.wav",
    "player/jockey/voice/idle/jockey_recognize10.wav",
    "player/jockey/voice/idle/jockey_recognize11.wav",
    "player/jockey/voice/idle/jockey_recognize13.wav",
    "player/jockey/voice/idle/jockey_recognize15.wav",
    "player/jockey/voice/idle/jockey_recognize17.wav",
    "player/jockey/voice/idle/jockey_recognize18.wav",
    "player/jockey/voice/idle/jockey_recognize20.wav",
    "player/jockey/voice/idle/jockey_recognize24.wav"
};
static char g_sChargerIdle[][] = {
    "player/charger/voice/idle/charger_lurk_01.wav",
    "player/charger/voice/idle/charger_lurk_02.wav",
    "player/charger/voice/idle/charger_lurk_03.wav",
    "player/charger/voice/idle/charger_lurk_05.wav",
    "player/charger/voice/idle/charger_lurk_06.wav",
    "player/charger/voice/idle/charger_lurk_08.wav",
    "player/charger/voice/idle/charger_lurk_09.wav",
    "player/charger/voice/idle/charger_lurk_10.wav"
};

public Plugin myinfo =
{
    name        = "L4D2 Silent SI Fix",
    author      = "Rainy",
    description = "특수좀비의 무음 문제를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_silent_si_fix"
};

public void OnPluginStart()
{
    g_hConVarAutoConvars = CreateConVar(
        "l4d2_silent_si_fix_auto_convars", "1",
        "ON/OFF auto convars updater. (1=ON, 0=OFF)",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_silent_si_fix");

    AddNormalSoundHook(SoundHook_Normal);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("charger_charge_end", Event_ChargerChargeEnd);
}

public void OnConfigsExecuted()
{
    if (!g_hConVarAutoConvars.BoolValue)
        return;

    // 리눅스 전용 서버에는 두 cvar가 없음
    ConVar maxSameSounds     = FindConVar("snd_max_same_sounds");
    ConVar multiplayerSounds = FindConVar("sv_multiplayer_sounds");
    if (maxSameSounds != null)
        maxSameSounds.IntValue = 8;
    if (multiplayerSounds != null)
        multiplayerSounds.IntValue = 40;
}

public void OnMapStart()
{
    PrecacheSounds(g_sSmokerAlert, sizeof(g_sSmokerAlert));
    PrecacheSounds(g_sHunterAlert, sizeof(g_sHunterAlert));
    PrecacheSounds(g_sJockeyAlert, sizeof(g_sJockeyAlert));
    PrecacheSounds(g_sChargerAlert, sizeof(g_sChargerAlert));
    PrecacheSounds(g_sSmokerIdle, sizeof(g_sSmokerIdle));
    PrecacheSounds(g_sHunterGrowl, sizeof(g_sHunterGrowl));
    PrecacheSounds(g_sJockeyIdle, sizeof(g_sJockeyIdle));
    PrecacheSounds(g_sChargerIdle, sizeof(g_sChargerIdle));

    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        // TIMER_FLAG_NO_MAPCHANGE로 이미 닫힌 핸들이라 delete하면 안 된다
        g_hIdleTimer[i] = null;
        // 게임 시간이 맵마다 0부터 다시 시작한다
        g_fAlertTime[i] = 0.0;
    }
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!IsInfected(client) || !IsPlayerAlive(client) || L4D_IsPlayerGhost(client))
        return;

    // 헌터는 웅크릴 때 growl 소리를, 자키는 가까운 생존자가 보이기 시작할 때 idle 소리를 즉시 내고 타이머를 다시 시작한다
    L4D2ZombieClassType zombieClass = L4D2_GetPlayerZombieClass(client);
    bool                cue;
    if (zombieClass == L4D2ZombieClass_Hunter)
        cue = (buttons & IN_DUCK) != 0;
    else if (zombieClass == L4D2ZombieClass_Jockey)
        cue = CanSeeSurvivor(client);
    else
        return;

    if (cue && !g_bIdleCue[client])
    {
        // 자키가 모퉁이에서 보였다 안 보였다 할 때 소리가 연달아 끊기지 않게 한 주기 안에는 다시 내지 않는다
        if (zombieClass == L4D2ZombieClass_Hunter || GetEngineTime() - g_fJockeyCueTime[client] >= JOCKEY_IDLE_INTERVAL)
        {
            g_fJockeyCueTime[client] = GetEngineTime();
            CreateIdleTimer(client);
            TriggerTimer(g_hIdleTimer[client], true);
        }
    }
    else if (!cue && g_bIdleCue[client] && zombieClass == L4D2ZombieClass_Hunter)
    {
        delete g_hIdleTimer[client];
    }
    g_bIdleCue[client] = cue;
}

void PrecacheSounds(const char[][] sounds, int count)
{
    for (int i = 0; i < count; i++)
        PrecacheSound(sounds[i], true);
}

bool TraceFilter_NoPlayers(int entity, int contentsMask)
{
    return entity > MaxClients;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_bIdleCue[i] = false;
        delete g_hIdleTimer[i];
    }
}

Action SoundHook_Normal(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    // 플러그인이 낸 소리는 그대로 통과시킨다
    if (!IsInfected(entity) || g_bEmitting[entity])
        return Plugin_Continue;

    // 플러그인이 방금 alert를 냈으면 엔진의 alert는 막는다 (같은 채널이라 겹치면 먼저 난 소리가 끊긴다)
    if (StrContains(sample, "/voice/alert/", false) != -1 && GetGameTime() - g_fAlertTime[entity] < ALERT_BLOCK_TIME)
        return Plugin_Stop;

    // 자키가 생존자에게 올라타고 있지 않으면 공격 소리 막기 (불필요한 소리 호출 버그 해결)
    if (StrContains(sample, "player/jockey/voice/attack/jockey_attackloop", false) != -1 && L4D_GetVictimJockey(entity) <= 0)
        return Plugin_Stop;

    switch (L4D2_GetPlayerZombieClass(entity))
    {
        case L4D2ZombieClass_Smoker:
        {
            // 스모커 타겟 포착 소리 막기 (타겟 포착 소리 재생 때문에 warn 소리가 차단되는 문제 해결)
            if (StrContains(sample, "player/smoker/voice/idle/smoker_spotprey", false) != -1)
                return Plugin_Stop;
            // 엔진이 내는 idle 소리 막기 (플러그인이 내는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/smoker/voice/idle/smoker_lurk", false) != -1)
                return Plugin_Stop;
            // warn 소리 재생하는 동안 idle 소리 중지
            if (StrContains(sample, "player/smoker/voice/warn/smoker_warn", false) != -1)
                CreateIdleTimer(entity);
        }
        case L4D2ZombieClass_Hunter:
        {
            // 엔진이 내는 growl 소리 막기 (플러그인이 내는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/hunter/voice/idle/hunter_stalk", false) != -1)
                return Plugin_Stop;
            // warn 소리 재생하는 동안 growl 소리 중지
            if (StrContains(sample, "player/hunter/voice/warn/hunter_warn", false) != -1)
                CreateIdleTimer(entity);
        }
        case L4D2ZombieClass_Jockey:
        {
            // 엔진이 내는 idle 소리 막기 (플러그인이 내는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/jockey/voice/idle/jockey_recognize", false) != -1)
                return Plugin_Stop;
        }
        case L4D2ZombieClass_Charger:
        {
            // 엔진이 내는 idle 소리 막기 (플러그인이 내는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/charger/voice/idle/charger_lurk", false) != -1)
                return Plugin_Stop;
            // 타겟 포착 소리 재생하는 동안 idle 소리 중지
            if (StrContains(sample, "player/charger/voice/idle/charger_spotprey", false) != -1)
                CreateIdleTimer(entity);
        }
    }

    return Plugin_Continue;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (!IsInfected(client))
        return;

    delete g_hIdleTimer[client];
    g_bIdleCue[client] = false;

    // 대전에서는 스폰 직후에 고스트가 되므로 다음 프레임에 고스트 여부를 확인한다
    RequestFrame(Frame_Spawned, userid);
}

void Frame_Spawned(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsInfected(client) && IsPlayerAlive(client) && !L4D_IsPlayerGhost(client))
        HandleSpawned(client);
}

public void L4D_OnMaterializeFromGhost(int client)
{
    if (IsInfected(client) && IsPlayerAlive(client))
        HandleSpawned(client);
}

void HandleSpawned(int client)
{
    L4D2ZombieClassType zombieClass = L4D2_GetPlayerZombieClass(client);

    // 스모커·헌터·자키·차저만 다룬다 (부머·스피터·탱크는 엔진 소리 그대로)
    if (GetIdleInterval(zombieClass) == 0.0)
        return;

    // 스폰과 실체화가 연달아 불려도 alert는 한 번만 낸다
    if (GetGameTime() - g_fAlertTime[client] >= 1.0)
    {
        g_fAlertTime[client] = GetGameTime();
        switch (zombieClass)
        {
            case L4D2ZombieClass_Smoker:
                EmitRandom(client, g_sSmokerAlert, sizeof(g_sSmokerAlert), 95, 95, 105);
            case L4D2ZombieClass_Hunter:
                EmitRandom(client, g_sHunterAlert, sizeof(g_sHunterAlert), 95, 100, 100);
            case L4D2ZombieClass_Jockey:
                EmitRandom(client, g_sJockeyAlert, sizeof(g_sJockeyAlert), 95, 100, 100);
            case L4D2ZombieClass_Charger:
                EmitRandom(client, g_sChargerAlert, sizeof(g_sChargerAlert), 105, 100, 100, 0.7);
        }
    }

    // 헌터는 idle 소리가 없고, 웅크리는 동안에만 growl 소리를 낸다
    if (zombieClass != L4D2ZombieClass_Hunter)
        CreateIdleTimer(client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsInfected(client))
        delete g_hIdleTimer[client];
}

public void L4D_ActivateAbility_Hunter_Post(int client, int ability)
{
    if (IsInfected(client))
        CreateIdleTimer(client);
}

public void L4D2_ActivateAbility_Charger_Post(int client, int ability)
{
    if (IsInfected(client))
        delete g_hIdleTimer[client];
}

void Event_ChargerChargeEnd(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsInfected(client))
        CreateIdleTimer(client);
}

// 타이머를 새로 만들어 다음 idle 소리를 한 주기 뒤로 미룬다. idle 소리가 없는 클래스는 타이머를 만들지 않는다
void CreateIdleTimer(int client)
{
    delete g_hIdleTimer[client];

    float interval = GetIdleInterval(L4D2_GetPlayerZombieClass(client));
    if (interval > 0.0)
        g_hIdleTimer[client] = CreateTimer(interval, Timer_Idle, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_Idle(Handle timer, any client)
{
    if (!IsInfected(client) || !IsPlayerAlive(client))
    {
        g_hIdleTimer[client] = null;
        return Plugin_Stop;
    }
    // 고스트이거나 생존자를 잡고 있는 동안은 소리만 건너뛰고 타이머는 유지한다
    if (L4D_IsPlayerGhost(client) || L4D2_GetSurvivorVictim(client) > 0)
        return Plugin_Continue;

    switch (L4D2_GetPlayerZombieClass(client))
    {
        case L4D2ZombieClass_Smoker:
            EmitRandom(client, g_sSmokerIdle, sizeof(g_sSmokerIdle), 85, 95, 105, 0.9);
        case L4D2ZombieClass_Hunter:
            EmitRandom(client, g_sHunterGrowl, sizeof(g_sHunterGrowl), 85, 90, 105);
        case L4D2ZombieClass_Jockey:
            EmitRandom(client, g_sJockeyIdle, sizeof(g_sJockeyIdle), 105, 100, 100);
        case L4D2ZombieClass_Charger:
            EmitRandom(client, g_sChargerIdle, sizeof(g_sChargerIdle), 85, 95, 105);
        default:
        {
            g_hIdleTimer[client] = null;
            return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}

void EmitRandom(int client, const char[][] sounds, int count, int level, int pitchMin, int pitchMax, float volume = 1.0, int channel = SNDCHAN_VOICE)
{
    g_bEmitting[client] = true;
    EmitSoundToAll(sounds[GetRandomInt(0, count - 1)], client, channel, level, SND_NOFLAGS, volume, GetRandomInt(pitchMin, pitchMax));
    g_bEmitting[client] = false;
}

// 살아 있는 생존자 중 한 명이라도 JOCKEY_CUE_RANGE 안에 있고 눈과 눈 사이가 막혀 있지 않으면 true (바라보는 방향은 따지지 않는다)
bool CanSeeSurvivor(int client)
{
    float eye[3], target[3];
    GetClientEyePosition(client, eye);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != L4D_TEAM_SURVIVOR || !IsPlayerAlive(i))
            continue;

        GetClientEyePosition(i, target);
        if (GetVectorDistance(eye, target, true) > JOCKEY_CUE_RANGE * JOCKEY_CUE_RANGE)
            continue;

        TR_TraceRayFilter(eye, target, MASK_VISIBLE, RayType_EndPoint, TraceFilter_NoPlayers);
        if (!TR_DidHit())
            return true;
    }
    return false;
}

float GetIdleInterval(L4D2ZombieClassType zombieClass)
{
    switch (zombieClass)
    {
        case L4D2ZombieClass_Smoker:
            return SMOKER_IDLE_INTERVAL;
        case L4D2ZombieClass_Hunter:
            return HUNTER_GROWL_INTERVAL;
        case L4D2ZombieClass_Jockey:
            return JOCKEY_IDLE_INTERVAL;
        case L4D2ZombieClass_Charger:
            return CHARGER_IDLE_INTERVAL;
    }
    return 0.0;
}

bool IsInfected(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == L4D_TEAM_INFECTED;
}
