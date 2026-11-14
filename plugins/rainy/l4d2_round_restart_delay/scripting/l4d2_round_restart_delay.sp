#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <hxlib>

enum
{
    REASON_DEFEAT = 1
};

bool g_bLateLoad;
bool g_bPluginStarted;

ConVar g_hConVarDelay;
float  g_fDelay;

public Plugin myinfo =
{
    name        = "L4D2 Round Restart Delay",
    author      = "Rainy",
    description = "라운드 재시작 지연 시간을 조정합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_round_restart_delay"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    g_bLateLoad = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hConVarDelay = CreateConVar(
        "l4d2_round_restart_delay", "0.5",
        "override the delay between round restarts. vanilla is 7.0",
        FCVAR_NOTIFY, true, 0.0);
    g_hConVarDelay.AddChangeHook(ConVarChanged_Update);
    g_fDelay = g_hConVarDelay.FloatValue;

    if (g_bLateLoad && LibraryExists(HXLIB_LIBRARY))
        StartPlugin();
}

public void OnAllPluginsLoaded()
{
    if (!g_bPluginStarted && LibraryExists(HXLIB_LIBRARY))
        StartPlugin();
}

public void OnLibraryAdded(const char[] name)
{
    if (!g_bPluginStarted && strcmp(name, HXLIB_LIBRARY) == 0)
        StartPlugin();
}

public void OnLibraryRemoved(const char[] name)
{
    if (strcmp(name, HXLIB_LIBRARY) == 0)
        StopPlugin();
}

void StartPlugin()
{
    g_bPluginStarted = true;
    HookEvent("round_end", Event_RoundEnd);
}

void StopPlugin()
{
    g_bPluginStarted = false;
    UnhookEvent("round_end", Event_RoundEnd);
}

void ConVarChanged_Update(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_fDelay = g_hConVarDelay.FloatValue;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("reason") != REASON_DEFEAT)
        return;

    HX_CountdownTimer timer = GetScenarioRestartTimer();
    if (timer.GetRemainingTime() <= 0.0)
        return;

    timer.Start(g_fDelay);
}
