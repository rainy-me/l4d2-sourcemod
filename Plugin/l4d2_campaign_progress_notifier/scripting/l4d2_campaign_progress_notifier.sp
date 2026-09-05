#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <left4dhooks>

ConVar g_hSoundEnabled;
ConVar g_hSoundVolume;
bool   g_bReachedPoint[3] = { false, ... };
Handle g_hUpdateTimer     = null;

public Plugin myinfo =
{
    name        = "L4D2 Campaign Progress Notifier",
    author      = "Rainy",
    description = "캠페인 진행 상황을 알립니다.",
    version     = "1.1.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_campaign_progress_notifier"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_campaign_progress_notifier.phrases");

    g_hSoundEnabled = CreateConVar(
        "l4d2_campaign_progress_notifier_sound_enabled", "1",
        "ON/OFF progress notification sound. (1=ON, 0=OFF)",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hSoundVolume = CreateConVar(
        "l4d2_campaign_progress_notifier_sound_volume", "0.8",
        "Progress notification sound volume.",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_campaign_progress_notifier");

    HookEvent("round_start", Event_RoundStart);

    RegConsoleCmd("sm_p", Cmd_Progress);
}

public void OnMapStart()
{
    if (g_hSoundEnabled.BoolValue)
    {
        PrecacheSound("ui/survival_teamrec.wav");
    }
}

public void OnMapEnd()
{
    for (int i = 0; i < 3; i++)
    {
        g_bReachedPoint[i] = false;
    }
    if (g_hUpdateTimer != null)
    {
        delete g_hUpdateTimer;
    }
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    char sGameMode[16];
    FindConVar("mp_gamemode").GetString(sGameMode, sizeof(sGameMode));
    if (sGameMode[0] != 's' && sGameMode[0] != 'v' && sGameMode[0] != 'h')
    {
        for (int i = 0; i < 3; i++)
        {
            g_bReachedPoint[i] = false;
        }
        if (g_hUpdateTimer != null)
        {
            delete g_hUpdateTimer;
        }
        g_hUpdateTimer = CreateTimer(1.0, Timer_CheckProgress, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

Action Timer_CheckProgress(Handle timer)
{
    int iFurthestFlow = RoundToFloor(L4D2_GetFurthestSurvivorFlow() / L4D2Direct_GetMapMaxFlowDistance() * 100.0);

    if (!g_bReachedPoint[0] && iFurthestFlow >= 25)
    {
        g_bReachedPoint[0] = true;
        NotifyPlayerProgress(25);
    }
    else if (!g_bReachedPoint[1] && iFurthestFlow >= 50)
    {
        g_bReachedPoint[1] = true;
        NotifyPlayerProgress(50);
    }
    else if (!g_bReachedPoint[2] && iFurthestFlow >= 75)
    {
        g_bReachedPoint[2] = true;
        NotifyPlayerProgress(75);
    }
    return Plugin_Continue;
}

void NotifyPlayerProgress(int iProgress)
{
    CPrintToChatAll("%t", "Furthest Progress", iProgress);
    if (g_hSoundEnabled.BoolValue)
    {
        EmitSoundToAll("ui/survival_teamrec.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO,
                       SNDLEVEL_NONE, SND_NOFLAGS, g_hSoundVolume.FloatValue);
    }
}

Action Cmd_Progress(int client, int args)
{
    if (!IsClient(client) || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Handled;
    }

    int iCurrentFlow = RoundFloat(L4D2Direct_GetFlowDistance(client) / L4D2Direct_GetMapMaxFlowDistance() * 100.0);
    CPrintToChatAll("%t", "Current Progress", client, iCurrentFlow);
    return Plugin_Handled;
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
