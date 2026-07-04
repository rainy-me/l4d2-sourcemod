#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define EF_DIMLIGHT 4

// true == ON, false == OFF
bool g_bFlashlightState[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 Idle Flashlight Fix",
    author      = "Rainy",
    description = "유휴 전 손전등 on/off 상태를 유휴 후에도 유지합니다.",
    version     = "1.0.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_flashlight_fix"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_bot_replace", Event_GoIdle);
    HookEvent("bot_player_replace", Event_ReturnFromIdle);
}

public void OnClientPutInServer(int client)
{
    g_bFlashlightState[client] = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_bFlashlightState[i] = false;
    }
}

Action Event_GoIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (IsClient(client) && IsClientInGame(client))
    {
        int iEffects = GetEntProp(client, Prop_Send, "m_fEffects");
        if (iEffects & EF_DIMLIGHT)
        {
            g_bFlashlightState[client] = true;
        }
        else
        {
            g_bFlashlightState[client] = false;
        }
    }
    return Plugin_Continue;
}

Action Event_ReturnFromIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (IsValidAliveClient(client))
    {
        DataPack pack = CreateDataPack();
        pack.WriteCell(client);
        pack.WriteCell(g_bFlashlightState[client]);
        RequestFrame(RestoreFlashlightState, pack);
    }
    return Plugin_Continue;
}

void RestoreFlashlightState(DataPack pack)
{
    pack.Reset();
    int  client           = pack.ReadCell();
    bool flashlight_state = pack.ReadCell();
    delete pack;

    if (IsValidAliveClient(client))
    {
        int iEffects = GetEntProp(client, Prop_Send, "m_fEffects");

        if (flashlight_state)
        {
            SetEntProp(client, Prop_Send, "m_fEffects", iEffects | EF_DIMLIGHT);
        }
        else
        {
            SetEntProp(client, Prop_Send, "m_fEffects", iEffects & ~EF_DIMLIGHT);
        }
    }
}

bool IsValidAliveClient(int client)
{
    return (IsClient(client) && IsClientInGame(client) && IsPlayerAlive(client));
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
