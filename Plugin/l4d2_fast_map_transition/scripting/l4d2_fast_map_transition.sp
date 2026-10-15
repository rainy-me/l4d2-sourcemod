#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <hxlib>

public Plugin myinfo =
{
    name        = "L4D2 Fast Map Transition",
    author      = "Rainy",
    description = "다음 챕터로 넘어가는 데 걸리는 시간을 줄여줍니다.",
    version     = "1.1.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_fast_map_transition"
};

ConVar g_cvTimescale;

public void OnPluginStart()
{
    g_cvTimescale = CreateConVar(
        "l4d2_fast_map_transition_timescale", "5.0",
        "맵 전환 시 적용할 타임스케일 값",
        FCVAR_NOTIFY, true, 1.0, true, 10.0);
    AutoExecConfig(true, "l4d2_fast_map_transition");

    FindConVar("changelevel_pause_interval").IntValue = 2;
    HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
}

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    SetTimescale(g_cvTimescale.FloatValue);
}
