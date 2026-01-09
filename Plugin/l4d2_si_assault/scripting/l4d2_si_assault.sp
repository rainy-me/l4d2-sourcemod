#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 SI Assault",
    author      = "Rainy",
    description = "모든 SI 봇이 대기하지 않고 생존자를 적극적으로 공격합니다.",
    version     = "1.2.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_si_assault"
};

bool   g_bLate;
ConVar g_hEnabled;
ConVar g_hAssaultInterval;
Handle g_hAssaultTimer = INVALID_HANDLE;

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
    g_hEnabled         = CreateConVar("si_assault_enabled", "1",
                                      "0 = Plugin OFF, 1 = Plugin ON",
                                      FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hAssaultInterval = CreateConVar("si_assault_interval", "10.0",
                                      "SI bot assault command execution interval (seconds)",
                                      FCVAR_NOTIFY, true, 0.1);
    g_hEnabled.AddChangeHook(OnConVarChanged);
    g_hAssaultInterval.AddChangeHook(OnConVarChanged);
    AutoExecConfig(true, "l4d2_si_assault");

    LateLoad();
}

void LateLoad()
{
    if (g_hEnabled.BoolValue && g_bLate && L4D_HasAnySurvivorLeftSafeArea())
    {
        g_hAssaultTimer = CreateTimer(g_hAssaultInterval.FloatValue, Timer_ForceExecuteAssault,
                                      _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    if (g_hEnabled.BoolValue)
    {
        g_hAssaultTimer = CreateTimer(g_hAssaultInterval.FloatValue, Timer_ForceExecuteAssault,
                                      _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_hAssaultTimer != INVALID_HANDLE)
    {
        KillTimer(g_hAssaultTimer);
    }

    if (g_hEnabled.BoolValue && L4D_HasAnySurvivorLeftSafeArea())
    {
        g_hAssaultTimer = CreateTimer(StringToFloat(newValue), Timer_ForceExecuteAssault,
                                      _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

Action Timer_ForceExecuteAssault(Handle timer)
{
    // PrintToChatAll("nb_assault!");
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
