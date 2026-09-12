#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Block Idle Reload",
    author      = "Rainy",
    description = "유휴 장전을 차단합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Archive/l4d2_block_idle_reload"
};

public void OnPluginStart()
{
    HookEvent("bot_player_replace", Event_BotPlayerReplace);    // 유휴 복귀
}

void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(0.01, Timer_UnReload, event.GetInt("player"), TIMER_FLAG_NO_MAPCHANGE);
}

void Timer_UnReload(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidSurvivor(client))
    {
        return;
    }

    for (int slot = 0; slot < 5; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon == -1)
        {
            continue;
        }

        if (HasEntProp(weapon, Prop_Send, "m_bInReload"))
        {
            SetEntProp(weapon, Prop_Send, "m_bInReload", 0);
        }

        if (HasEntProp(weapon, Prop_Send, "m_reloadState"))
        {
            SetEntProp(weapon, Prop_Send, "m_reloadState", 0);

            if (GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == weapon)
            {
                SwitchAwayFrom(client, slot);
            }
        }
    }
}

void SwitchAwayFrom(int client, int activeSlot)
{
    static const int order[] = { 1, 2, 3, 4, 0 };

    for (int i = 0; i < sizeof(order); i++)
    {
        int slot = order[i];
        if (slot == activeSlot)
        {
            continue;
        }

        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon == -1)
        {
            continue;
        }

        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        FakeClientCommand(client, "use %s", classname);
        return;
    }

    // 바꿀 무기가 없으면 손을 비워서 재장착을 유도한다.
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
    CreateTimer(0.1, Timer_ClearActiveWeapon, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void Timer_ClearActiveWeapon(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidSurvivor(client) && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != -1)
    {
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
    }
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
