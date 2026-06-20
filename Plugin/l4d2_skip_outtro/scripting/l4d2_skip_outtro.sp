#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Skip Outtro",
    author      = "Rainy",
    description = "맵 클리어 시 아웃트로를 빠르게 건너뜁니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_skip_outtro"
};

public void OnPluginStart()
{
    HookEvent("finale_vehicle_leaving", Event_FinaleVehicleLeaving, EventHookMode_PostNoCopy);
    HookEvent("finale_win", Event_FinaleWin, EventHookMode_PostNoCopy);
}

void Event_FinaleVehicleLeaving(Event event, const char[] name, bool dontBroadcast)
{
    ServerCommand("scripted_user_func timescale,10");
}

void Event_FinaleWin(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(0.1, Timer_OuttroStatsDone, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_OuttroStatsDone(Handle timer)
{
    ServerCommand("outtro_stats_done");
    return Plugin_Continue;
}
