#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Hang Fall Death Defib Fix",
    author      = "Rainy",
    description = "매달리는 중에 떨어져 사망한 생존자의 소생 불가 버그를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_hang_fall_death_defib_fix"
};

public void OnPluginStart()
{
    HookEvent("player_hurt", Event_PlayerHurt);
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("health") > 0)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || GetClientTeam(client) != 2)
        return;

    if (GetEntProp(client, Prop_Send, "m_isFallingFromLedge") == 0)
        return;

    // Force incap state before the death model spawns, so it uses
    // the incap death animation instead of the hanging pose.
    SetEntProp(client, Prop_Send, "m_isIncapacitated", 1);
    SetEntProp(client, Prop_Send, "m_isFallingFromLedge", 0);
}
