#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Fast Map Transition",
    author      = "Rainy",
    description = "다음 챕터로 넘어가는 데 걸리는 시간을 줄여줍니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_fast_map_transition"
};

public void OnPluginStart()
{
    FindConVar("changelevel_pause_interval").IntValue = 2;
    HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
}

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    ServerCommand("scripted_user_func timescale,10");
}