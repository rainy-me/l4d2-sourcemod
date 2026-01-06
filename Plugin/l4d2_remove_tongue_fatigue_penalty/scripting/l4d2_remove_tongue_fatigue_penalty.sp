#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Remove Tongue Fatigue Penalty",
    author      = "Rainy",
    description = "스모커 혀에서 풀려났을 때 움직이지 못하는 페널티를 제거합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_remove_tongue_fatigue_penalty"
};

ConVar g_hTongueReleaseFatiguePenalty = null;

public void OnPluginStart()
{
    g_hTongueReleaseFatiguePenalty = FindConVar("tongue_release_fatigue_penalty");
    if (g_hTongueReleaseFatiguePenalty == null)
    {
        SetFailState("Could not find ConVar 'tongue_release_fatigue_penalty'");
    }

    SetConVarInt(g_hTongueReleaseFatiguePenalty, 0);
    PrintToServer("Set 'tongue_release_fatigue_penalty' to 0");
}

// 맵 로드 시에도 값을 유지
public void OnConfigsExecuted()
{
    if (g_hTongueReleaseFatiguePenalty != null)
    {
        SetConVarInt(g_hTongueReleaseFatiguePenalty, 0);
    }
}