#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define SMOKER_SOUND_INTERVAL  2.45
#define HUNTER_SOUND_INTERVAL  2.6
#define JOCKEY_SOUND_INTERVAL  1.8
#define CHARGER_SOUND_INTERVAL 1.7

public Plugin myinfo =
{
    name        = "L4D2 Fix SI Sound",
    author      = "Rainy",
    description = "특수좀비의 소리 문제를 개선합니다.",
    version     = "1.1.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_fix_si_sound"
};

ConVar      g_hAutoConvars;

bool        g_bHunterWasDucking[MAXPLAYERS + 1]  = { false, ... };

// Flags to indicate if the plugin is emitting the sound
bool        g_bEmitSmokerSound[MAXPLAYERS + 1]   = { false, ... };
bool        g_bEmitHunterSound[MAXPLAYERS + 1]   = { false, ... };
bool        g_bEmitJockeySound[MAXPLAYERS + 1]   = { false, ... };
bool        g_bEmitChargerSound[MAXPLAYERS + 1]  = { false, ... };

// Timer handles for each special infected sound emitter
Handle      g_hSmokerSoundTimer[MAXPLAYERS + 1]  = { null, ... };
Handle      g_hHunterSoundTimer[MAXPLAYERS + 1]  = { null, ... };
Handle      g_hJockeySoundTimer[MAXPLAYERS + 1]  = { null, ... };
Handle      g_hChargerSoundTimer[MAXPLAYERS + 1] = { null, ... };

// Sound file arrays for each special infected
static char g_sSmokerSound[][]                   = {
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
static char g_sHunterSound[][] = {
    "player/hunter/voice/idle/hunter_stalk_04.wav",
    "player/hunter/voice/idle/hunter_stalk_05.wav",
    "player/hunter/voice/idle/hunter_stalk_06.wav",
    "player/hunter/voice/idle/hunter_stalk_07.wav",
    "player/hunter/voice/idle/hunter_stalk_08.wav",
    "player/hunter/voice/idle/hunter_stalk_09.wav"
};
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
static char g_sChargerSound[][] = {
    "player/charger/voice/idle/charger_lurk_01.wav",
    "player/charger/voice/idle/charger_lurk_02.wav",
    "player/charger/voice/idle/charger_lurk_03.wav",
    "player/charger/voice/idle/charger_lurk_05.wav",
    "player/charger/voice/idle/charger_lurk_06.wav",
    "player/charger/voice/idle/charger_lurk_08.wav",
    "player/charger/voice/idle/charger_lurk_09.wav",
    "player/charger/voice/idle/charger_lurk_10.wav"
};

public void OnPluginStart()
{
    g_hAutoConvars = CreateConVar("l4d2_fix_si_sound_auto_convars", "1",
                                  "ON/OFF auto convars updater. (1=ON, 0=OFF)",
                                  FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_fix_si_sound");

    AutoConvars(g_hAutoConvars.BoolValue);
    AddNormalSoundHook(SoundHook);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("charger_charge_end", Event_ChargerChargeEnd);
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(g_sSmokerSound); i++)
    {
        PrecacheSound(g_sSmokerSound[i], true);
    }
    for (int i = 0; i < sizeof(g_sJockeySound); i++)
    {
        PrecacheSound(g_sJockeySound[i], true);
    }
    for (int i = 0; i < sizeof(g_sHunterSound); i++)
    {
        PrecacheSound(g_sHunterSound[i], true);
    }
    for (int i = 0; i < sizeof(g_sChargerSound); i++)
    {
        PrecacheSound(g_sChargerSound[i], true);
    }

    // avoid invalid timer handle exceptions after map transitions
    for (int i = 1; i <= MAXPLAYERS; i++)
    {
        g_hSmokerSoundTimer[i]  = null;
        g_hHunterSoundTimer[i]  = null;
        g_hJockeySoundTimer[i]  = null;
        g_hChargerSoundTimer[i] = null;
    }
}

void AutoConvars(bool enable)
{
    if (enable)
    {
        ConVar snd_max_same_sounds     = FindConVar("snd_max_same_sounds");
        ConVar sv_multiplayer_sounds   = FindConVar("sv_multiplayer_sounds");
        snd_max_same_sounds.IntValue   = 16;
        sv_multiplayer_sounds.IntValue = 64;
    }
}

Action SoundHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (!IsClient(entity) || !IsClientInGame(entity) || GetClientTeam(entity) != L4D_TEAM_INFECTED)
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
            // 게임 엔진에서 재생하는 idle 소리 막기 (플러그인에서 강제로 재생하는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/smoker/voice/idle/smoker_lurk", false) != -1 && !g_bEmitSmokerSound[entity])
            {
                return Plugin_Stop;
            }
            // warn 소리 재생하는 동안 idle 소리 중지
            if (StrContains(sample, "player/smoker/voice/warn/smoker_warn", false) != -1)
            {
                CreateSmokerSoundTimer(entity);
                return Plugin_Continue;
            }
        }
        case L4D2ZombieClass_Hunter:
        {
            // 게임 엔진에서 재생하는 idle 소리 막기 (플러그인에서 강제로 재생하는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/hunter/voice/idle/hunter_stalk", false) != -1 && !g_bEmitHunterSound[entity])
            {
                return Plugin_Stop;
            }
            // warn 소리 재생하는 동안 idle 소리 중지
            if (StrContains(sample, "player/hunter/voice/warn/hunter_warn", false) != -1)
            {
                CreateHunterSoundTimer(entity);
                return Plugin_Continue;
            }
        }
        case L4D2ZombieClass_Jockey:
        {
            // 게임 엔진에서 재생하는 idle 소리 막기 (플러그인에서 강제로 재생하는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/jockey/voice/idle/jockey_recognize", false) != -1 && !g_bEmitJockeySound[entity])
            {
                return Plugin_Stop;
            }
        }
        case L4D2ZombieClass_Charger:
        {
            // 게임 엔진에서 재생하는 idle 소리 막기 (플러그인에서 강제로 재생하는 소리와 중복 재생되는 문제 해결)
            if (StrContains(sample, "player/charger/voice/idle/charger_lurk", false) != -1 && !g_bEmitChargerSound[entity])
            {
                return Plugin_Stop;
            }
            // 타겟 포착 소리 재생하는 동안 idle 소리 중지
            if (StrContains(sample, "player/charger/voice/idle/charger_spotprey", false) != -1)
            {
                CreateChargerSoundTimer(entity);
                return Plugin_Continue;
            }
        }
    }

    return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        return;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Hunter)
    {
        return;
    }

    bool isDucking = (buttons & IN_DUCK) != 0;
    if (isDucking && !g_bHunterWasDucking[client])
    {
        CreateHunterSoundTimer(client);
        TriggerTimer(g_hHunterSoundTimer[client], true);
    }
    else if (!isDucking && g_bHunterWasDucking[client])
    {
        KillHunterSoundTimer(client);
    }
    g_bHunterWasDucking[client] = isDucking;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        return;
    }

    // This will also trigger if you switch to Tank
    KillSmokerSoundTimer(client);
    KillHunterSoundTimer(client);
    KillJockeySoundTimer(client);
    KillChargerSoundTimer(client);

    int zClass = L4D2_GetPlayerZombieClass(client);
    switch (zClass)
    {
        case L4D2ZombieClass_Smoker:
        {
            CreateSmokerSoundTimer(client);
        }
        case L4D2ZombieClass_Hunter:
        {
            g_bHunterWasDucking[client] = false;
        }
        case L4D2ZombieClass_Jockey:
        {
            CreateJockeySoundTimer(client);
        }
        case L4D2ZombieClass_Charger:
        {
            CreateChargerSoundTimer(client);
        }
    }
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        return;
    }

    int zClass = L4D2_GetPlayerZombieClass(client);
    switch (zClass)
    {
        case L4D2ZombieClass_Smoker:
        {
            KillSmokerSoundTimer(client);
        }
        case L4D2ZombieClass_Hunter:
        {
            KillHunterSoundTimer(client);
        }
        case L4D2ZombieClass_Jockey:
        {
            KillJockeySoundTimer(client);
        }
        case L4D2ZombieClass_Charger:
        {
            KillChargerSoundTimer(client);
        }
    }
}

public void L4D_ActivateAbility_Hunter_Post(int client, int ability)
{
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    CreateHunterSoundTimer(client);
}

public void L4D2_ActivateAbility_Charger_Post(int client, int ability)
{
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    KillChargerSoundTimer(client);
}

void Event_ChargerChargeEnd(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client))
    {
        return;
    }

    CreateChargerSoundTimer(client);
}

void CreateSmokerSoundTimer(int client)
{
    KillSmokerSoundTimer(client);
    g_hSmokerSoundTimer[client] = CreateTimer(SMOKER_SOUND_INTERVAL, EmitSmokerSound, client,
                                              TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void KillSmokerSoundTimer(int client)
{
    if (g_hSmokerSoundTimer[client] != null)
    {
        delete g_hSmokerSoundTimer[client];
    }
}

void CreateHunterSoundTimer(int client)
{
    KillHunterSoundTimer(client);
    g_hHunterSoundTimer[client] = CreateTimer(HUNTER_SOUND_INTERVAL, EmitHunterSound, client,
                                              TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void KillHunterSoundTimer(int client)
{
    if (g_hHunterSoundTimer[client] != null)
    {
        delete g_hHunterSoundTimer[client];
    }
}

void CreateJockeySoundTimer(int client)
{
    KillJockeySoundTimer(client);
    g_hJockeySoundTimer[client] = CreateTimer(JOCKEY_SOUND_INTERVAL, EmitJockeySound, client,
                                              TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void KillJockeySoundTimer(int client)
{
    if (g_hJockeySoundTimer[client] != null)
    {
        delete g_hJockeySoundTimer[client];
    }
}

void CreateChargerSoundTimer(int client)
{
    KillChargerSoundTimer(client);
    g_hChargerSoundTimer[client] = CreateTimer(CHARGER_SOUND_INTERVAL, EmitChargerSound, client,
                                               TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void KillChargerSoundTimer(int client)
{
    if (g_hChargerSoundTimer[client] != null)
    {
        delete g_hChargerSoundTimer[client];
    }
}

Action EmitSmokerSound(Handle timer, any client)
{
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || L4D_IsPlayerGhost(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        g_hSmokerSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Smoker)
    {
        g_hSmokerSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D_GetVictimSmoker(client) != 0)
    {
        return Plugin_Continue;
    }

    int rndPick                = GetRandomInt(0, (sizeof(g_sSmokerSound) - 1));
    g_bEmitSmokerSound[client] = true;
    EmitSoundToAll(g_sSmokerSound[rndPick], client, SNDCHAN_VOICE, 85, SND_NOFLAGS, 0.9);
    g_bEmitSmokerSound[client] = false;
    return Plugin_Continue;
}

Action EmitHunterSound(Handle timer, any client)
{
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || L4D_IsPlayerGhost(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        g_hHunterSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Hunter)
    {
        g_hHunterSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D_GetVictimHunter(client) != 0)
    {
        return Plugin_Continue;
    }

    int rndPick                = GetRandomInt(0, sizeof(g_sHunterSound) - 1);
    g_bEmitHunterSound[client] = true;
    EmitSoundToAll(g_sHunterSound[rndPick], client, SNDCHAN_VOICE, 85);
    g_bEmitHunterSound[client] = false;
    return Plugin_Continue;
}

Action EmitJockeySound(Handle timer, any client)
{
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || L4D_IsPlayerGhost(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        g_hJockeySoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Jockey)
    {
        g_hJockeySoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D_GetVictimJockey(client) != 0)
    {
        return Plugin_Continue;
    }

    int rndPick                = GetRandomInt(0, (sizeof(g_sJockeySound) - 1));
    g_bEmitJockeySound[client] = true;
    EmitSoundToAll(g_sJockeySound[rndPick], client, SNDCHAN_VOICE, SNDLEVEL_HELICOPTER);
    g_bEmitJockeySound[client] = false;
    return Plugin_Continue;
}

Action EmitChargerSound(Handle timer, any client)
{
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || L4D_IsPlayerGhost(client) || GetClientTeam(client) != L4D_TEAM_INFECTED)
    {
        g_hChargerSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D2_GetPlayerZombieClass(client) != L4D2ZombieClass_Charger)
    {
        g_hChargerSoundTimer[client] = null;
        return Plugin_Stop;
    }
    if (L4D_GetVictimCharger(client) != 0)
    {
        return Plugin_Continue;
    }

    int rndPick                 = GetRandomInt(0, (sizeof(g_sChargerSound) - 1));
    g_bEmitChargerSound[client] = true;
    EmitSoundToAll(g_sChargerSound[rndPick], client, SNDCHAN_VOICE, 85);
    g_bEmitChargerSound[client] = false;
    return Plugin_Continue;
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
