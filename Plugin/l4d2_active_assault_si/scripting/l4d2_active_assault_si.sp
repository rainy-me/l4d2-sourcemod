#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Active Assault SI",
    author      = "Rainy",
    description = "모든 SI 봇이 대기하지 않고 생존자를 적극적으로 공격합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_active_assault_si"
};

bool   g_bLate;
Handle g_hAssaultTimer = INVALID_HANDLE;
ConVar g_hCvarAssaultInterval;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_Failure;
    }

    g_bLate = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hCvarAssaultInterval = CreateConVar("si_assault_interval", "5.0", "SI bot assault command execution interval (seconds)",
                                          FCVAR_NOTIFY, true, 0.1);
    g_hCvarAssaultInterval.AddChangeHook(OnConVarChange);
    AutoExecConfig(true, "l4d2_active_assault_si");

    LateLoad();
}

void LateLoad()
{
    if (g_bLate && L4D_HasAnySurvivorLeftSafeArea())
    {
        g_hAssaultTimer = CreateTimer(g_hCvarAssaultInterval.FloatValue, Timer_ForceExecuteAssault,
                                      _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    g_hAssaultTimer = CreateTimer(g_hCvarAssaultInterval.FloatValue, Timer_ForceExecuteAssault,
                                  _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_hCvarAssaultInterval && L4D_HasAnySurvivorLeftSafeArea())
    {
        if (g_hAssaultTimer != INVALID_HANDLE)
        {
            KillTimer(g_hAssaultTimer);
        }
        float interval  = StringToFloat(newValue);
        g_hAssaultTimer = CreateTimer(interval, Timer_ForceExecuteAssault, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

Action Timer_ForceExecuteAssault(Handle timer)
{
    CheatServerCommand("nb_assault");
    return Plugin_Continue;
}

void CheatServerCommand(char[] command)
{
    int flags = GetCommandFlags(command);
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    ServerCommand("%s", command);
    ServerExecute();
    SetCommandFlags(command, flags);
}
