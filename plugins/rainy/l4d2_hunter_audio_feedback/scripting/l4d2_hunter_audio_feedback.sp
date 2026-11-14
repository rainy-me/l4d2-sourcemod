#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <hxlib>

ConVar g_hConVarAlwaysShriek;
bool   g_bAlwaysShriek;

ConVar g_hConVarHonestWarn;
bool   g_bHonestWarn;

int    g_iOffsetPounceSoundCooldown;
bool   g_bLateLoaded;

public Plugin myinfo =
{
    name        = "L4D2 Hunter Audio Feedback",
    author      = "Rainy",
    description = "헌터가 도약할 때 항상 소리를 내도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_hunter_audio_feedback"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    g_bLateLoaded = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hConVarAlwaysShriek = CreateConVar(
        "l4d2_hunter_audio_feedback_always_shrieks", "1",
        "hunters will always shriek when they lunge",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hConVarAlwaysShriek.AddChangeHook(ConVarChanged_Update);

    g_hConVarHonestWarn = CreateConVar(
        "l4d2_hunter_audio_feedback_honest_warn", "1",
        "hunters won't warn about their lunge if they're already lunging",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hConVarHonestWarn.AddChangeHook(ConVarChanged_Update);

    ReadConVars();

    HookEvent("ability_use", Event_AbilityUse);
    g_iOffsetPounceSoundCooldown = FindSendPropInfo("CTerrorPlayer", "m_pounceStartPosition");
    g_iOffsetPounceSoundCooldown += 52;

    if (g_bLateLoaded)
        HXLibRescanForwards();
}

void ConVarChanged_Update(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ReadConVars();
}

void ReadConVars()
{
    g_bAlwaysShriek = g_hConVarAlwaysShriek.BoolValue;
    g_bHonestWarn   = g_hConVarHonestWarn.BoolValue;
}

void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bAlwaysShriek)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client && GetZombieClass(client) == ZClass_Hunter && event.GetInt("context"))
        SetEntData(client, g_iOffsetPounceSoundCooldown, -1.0);
}

public Action OnVocalize(int client, char gameSound[64], float &cooldown, float &durationAI)
{
    if (!g_bHonestWarn || !IsValidClient(client) || GetZombieClass(client) != ZClass_Hunter)
        return Plugin_Continue;

    if (IsHunterLunging(client) && strcmp(gameSound, "HunterZombie.Warn") == 0)
        return Plugin_Handled;

    return Plugin_Continue;
}
