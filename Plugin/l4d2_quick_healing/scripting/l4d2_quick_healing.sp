#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <left4dhooks>

ConVar g_hHealPercent;
bool   g_bFastHealUsed[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 Quick Healing",
    author      = "Rainy",
    description = "시작 은신처 내에서 1회 한정 킷을 즉시 사용할 수 있습니다.",
    version     = "1.2.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_quick_healing"
};

public void OnPluginStart()
{
    g_hHealPercent = FindConVar("first_aid_heal_percent");

    HookEvent("round_start", Event_RoundStart);
    HookEvent("heal_begin", Event_HealBegin);
}

public void OnMapStart()
{
    PrecacheSound("ui/littlereward.wav");
}

public void OnClientPutInServer(int client)
{
    g_bFastHealUsed[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_bFastHealUsed[client] = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i < sizeof(g_bFastHealUsed); i++)
    {
        g_bFastHealUsed[i] = false;
    }
}

void Event_HealBegin(Event event, const char[] name, bool dontBroadcast)
{
    int healer = GetClientOfUserId(event.GetInt("userid"));
    int healee = GetClientOfUserId(event.GetInt("subject"));
    if (!IsValidClient(healer) || !IsValidClient(healee))
    {
        return;
    }

    if (g_bFastHealUsed[healee] || !L4D_IsInFirstCheckpoint(healee))
    {
        return;
    }

    // Use quick healing
    g_bFastHealUsed[healee] = true;
    int rawHealth           = GetClientHealth(healee);
    int newHealth           = RoundToFloor(float(rawHealth) + (100.0 - float(rawHealth)) * g_hHealPercent.FloatValue);
    SetEntityHealth(healee, newHealth);
    L4D_SetTempHealth(healee, 0.0);
    L4D_SetPlayerReviveCount(healee, 0);
    L4D_SetPlayerThirdStrikeState(healee, false);
    L4D_SetPlayerIsGoingToDie(healee, false);

    // Notify quick healing use
    if (healer == healee)
    {
        PrintToChat(healee, "Quick healing used");
        EmitSoundToClient(healee, "ui/littlereward.wav");
    }
    else
    {
        CPrintToChat(healee, "{green}%N{default} quick healed you", healer);
        CPrintToChat(healer, "Used quick healing to {green}%N", healee);
        EmitSoundToClient(healee, "ui/littlereward.wav");
        EmitSoundToClient(healer, "ui/littlereward.wav");
    }

    // Stagger healer and cancel immediately
    L4D_StaggerPlayer(healer, healee, NULL_VECTOR);
    CreateTimer(0.1, Timer_CancelStagger, GetClientUserId(healer));

    // Remove the healer's first aid kit.
    int weapon = GetPlayerWeaponSlot(healer, 3);
    if (weapon != -1)
    {
        RemovePlayerItem(healer, weapon);
    }
}

void Timer_CancelStagger(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client))
    {
        L4D_CancelStagger(client);
    }
}

bool IsValidClient(int index)
{
    return index > 0 && index <= MaxClients && IsClientInGame(index);
}
