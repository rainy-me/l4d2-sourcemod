#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define MAX_WEAPON_SLOTS    5
#define SWITCH_WAIT_FRAMES  50

float g_fIdleAngles[MAXPLAYERS + 1][3];
bool  g_bHasIdleAngles[MAXPLAYERS + 1]    = { false, ... };
bool  g_bIdleMagnumReload[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "L4D2 Idle View Fix",
    author      = "Rainy",
    description = "유휴 전 시야각을 유휴 복귀 후에도 유지하고, 매그넘 재장전 중 유휴 복귀 시 시야 흔들림을 없앱니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_view_fix"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_bot_replace", Event_GoIdle);
    HookEvent("bot_player_replace", Event_ReturnFromIdle);
}

public void OnClientPutInServer(int client)
{
    g_bHasIdleAngles[client]    = false;
    g_bIdleMagnumReload[client] = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_bHasIdleAngles[i]    = false;
        g_bIdleMagnumReload[i] = false;
    }
}

Action Event_GoIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (IsClient(client) && IsClientInGame(client))
    {
        GetClientEyeAngles(client, g_fIdleAngles[client]);
        g_bHasIdleAngles[client]    = true;
        g_bIdleMagnumReload[client] = IsReloadingMagnum(GetClientOfUserId(event.GetInt("bot")));
    }
    return Plugin_Continue;
}

Action Event_ReturnFromIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    // 유휴 기록이 없는 봇 인수(라운드 시작 시 합류 등)는 건드리지 않음
    if (IsValidAliveClient(client) && g_bHasIdleAngles[client])
    {
        g_bHasIdleAngles[client] = false;
        RequestFrame(RestoreViewAngles, GetClientUserId(client));

        if (g_bIdleMagnumReload[client])
        {
            g_bIdleMagnumReload[client] = false;
            RedeployMagnum(client);
        }
    }
    return Plugin_Continue;
}

void RestoreViewAngles(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidAliveClient(client))
    {
        TeleportEntity(client, NULL_VECTOR, g_fIdleAngles[client], NULL_VECTOR);
    }
}

// 매그넘 재장전 중 유휴하면 클라이언트의 1인칭 재장전 애니메이션이 멈춰 있다가 복귀 시 이어서 재생되며 시야가 2도가량 흔들림
// 클라이언트가 직접 다른 슬롯으로 바꿨다가 다시 꺼내게 해서 그 애니메이션을 덮어씀
void RedeployMagnum(int client)
{
    int magnum = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsMagnum(magnum))
    {
        return;
    }

    int current = -1, other = -1;
    for (int i = 0; i < MAX_WEAPON_SLOTS; i++)
    {
        int weapon = GetPlayerWeaponSlot(client, i);
        if (weapon == magnum)
        {
            current = i;
        }
        else if (weapon != -1 && other == -1)
        {
            other = i;
        }
    }
    if (current == -1 || other == -1)
    {
        return;
    }

    ClientCommand(client, "slot%d", other + 1);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(EntIndexToEntRef(magnum));
    pack.WriteCell(current + 1);
    pack.WriteCell(GetGameTickCount() + SWITCH_WAIT_FRAMES);
    RequestFrame(Frame_SwitchBack, pack);
}

// 두 명령을 한꺼번에 보내면 클라이언트가 무기를 바꾸기 전에 원래 슬롯을 다시 골라 아무 일도 안 일어날 수 있어서,
// 실제로 무기가 바뀐 것을 확인한 프레임에 바로 매그넘으로 되돌림
void Frame_SwitchBack(DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int magnum = EntRefToEntIndex(pack.ReadCell());
    int slot   = pack.ReadCell();
    int expire = pack.ReadCell();

    if (!IsValidAliveClient(client) || magnum == INVALID_ENT_REFERENCE)
    {
        delete pack;
        return;
    }

    if (GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != magnum || GetGameTickCount() >= expire)
    {
        delete pack;
        ClientCommand(client, "slot%d", slot);
        return;
    }

    RequestFrame(Frame_SwitchBack, pack);
}

bool IsReloadingMagnum(int client)
{
    if (!IsValidAliveClient(client))
    {
        return false;
    }
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    return IsMagnum(weapon) && GetEntProp(weapon, Prop_Data, "m_bInReload") != 0;
}

bool IsMagnum(int weapon)
{
    char cls[32];
    return weapon > 0 && IsValidEntity(weapon) && GetEntityClassname(weapon, cls, sizeof(cls)) && StrEqual(cls, "weapon_pistol_magnum");
}

bool IsValidAliveClient(int client)
{
    return (IsClient(client) && IsClientInGame(client) && IsPlayerAlive(client));
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
