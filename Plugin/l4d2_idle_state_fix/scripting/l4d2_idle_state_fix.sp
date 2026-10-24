#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define MAX_WEAPON_SLOTS   5
#define SWITCH_WAIT_FRAMES 50
#define EF_DIMLIGHT        4

ConVar g_hAdrenalineDuration;
float  g_fIdleAngles[MAXPLAYERS + 1][3];
bool   g_bHasIdleState[MAXPLAYERS + 1]      = { false, ... };
int    g_iIdleBotUserId[MAXPLAYERS + 1]     = { 0, ... };
bool   g_bIdleMagnumReload[MAXPLAYERS + 1]  = { false, ... };
bool   g_bIdleFlashlight[MAXPLAYERS + 1]    = { false, ... };
float  g_fAdrenalineEndTime[MAXPLAYERS + 1] = { 0.0, ... };

public Plugin myinfo =
{
    name        = "L4D2 Idle State Fix",
    author      = "Rainy",
    description = "유휴 복귀 시 시야, 손전등, 아드레날린 상태를 유휴 전과 같게 유지합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_state_fix"
};

public void OnPluginStart()
{
    g_hAdrenalineDuration = FindConVar("adrenaline_duration");

    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_bot_replace", Event_GoIdle);
    HookEvent("bot_player_replace", Event_ReturnFromIdle);
    HookEvent("adrenaline_used", Event_AdrenalineUsed);
    HookEvent("player_incapacitated", Event_ResetState);
    HookEvent("player_death", Event_ResetState);
}

public void OnClientPutInServer(int client)
{
    g_bHasIdleState[client]      = false;
    g_bIdleMagnumReload[client]  = false;
    g_fAdrenalineEndTime[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
    g_fAdrenalineEndTime[client] = 0.0;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_bHasIdleState[i]      = false;
        g_bIdleMagnumReload[i]  = false;
        g_fAdrenalineEndTime[i] = 0.0;
    }
}

void Event_AdrenalineUsed(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidAliveClient(client))
    {
        return;
    }

    float fEndTime = GetGameTime() + g_hAdrenalineDuration.FloatValue;
    g_fAdrenalineEndTime[client] = fEndTime;

    // 유휴 중에는 봇 기준으로 이벤트가 오므로 유휴 플레이어에게도 기록
    int idlePlayer = GetIdlePlayer(client);
    if (idlePlayer != 0)
    {
        g_fAdrenalineEndTime[idlePlayer] = fEndTime;
    }
}

void Event_ResetState(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client))
    {
        return;
    }

    g_fAdrenalineEndTime[client] = 0.0;

    // 유휴 중에는 봇 기준으로 이벤트가 오므로 유휴 플레이어 기록도 지움
    int idlePlayer = GetIdlePlayer(client);
    if (idlePlayer == 0)
    {
        return;
    }

    g_fAdrenalineEndTime[idlePlayer] = 0.0;

    // 유휴 중 봇이 죽으면 나중에 다른 봇을 넘겨받을 때 예전 시야/손전등을 되돌리지 않도록 유휴 기록도 지움
    if (StrEqual(name, "player_death"))
    {
        g_bHasIdleState[idlePlayer]     = false;
        g_bIdleMagnumReload[idlePlayer] = false;
    }
}

void Event_GoIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (IsClient(client) && IsClientInGame(client))
    {
        GetClientEyeAngles(client, g_fIdleAngles[client]);
        g_bHasIdleState[client]     = true;
        g_iIdleBotUserId[client]    = event.GetInt("bot");
        g_bIdleMagnumReload[client] = IsReloadingMagnum(GetClientOfUserId(event.GetInt("bot")));
        g_bIdleFlashlight[client]   = (GetEntProp(client, Prop_Send, "m_fEffects") & EF_DIMLIGHT) != 0;
    }
}

void Event_ReturnFromIdle(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (!IsValidAliveClient(client))
    {
        return;
    }

    // 유휴 기록이 없는 봇 인수(라운드 시작 시 합류 등)는 건드리지 않음
    if (!g_bHasIdleState[client])
    {
        return;
    }

    g_bHasIdleState[client] = false;

    // 관전/팀 이동 후 다른 봇을 넘겨받은 경우에는 예전 상태를 되돌리지 않음
    if (event.GetInt("bot") != g_iIdleBotUserId[client])
    {
        return;
    }

    float fRemaining = g_fAdrenalineEndTime[client] - GetGameTime();
    if (fRemaining > 0.0)
    {
        L4D2_UseAdrenaline(client, fRemaining, false, false);
    }

    RequestFrame(RestoreViewAngles, GetClientUserId(client));

    if (g_bIdleMagnumReload[client])
    {
        g_bIdleMagnumReload[client] = false;
        RedeployMagnum(client);
    }
}

void RestoreViewAngles(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidAliveClient(client))
    {
        TeleportEntity(client, NULL_VECTOR, g_fIdleAngles[client], NULL_VECTOR);

        int iEffects = GetEntProp(client, Prop_Send, "m_fEffects");
        SetEntProp(client, Prop_Send, "m_fEffects", g_bIdleFlashlight[client] ? (iEffects | EF_DIMLIGHT) : (iEffects & ~EF_DIMLIGHT));
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

// 유휴 플레이어가 있는 봇이면 그 플레이어를, 아니면 0을 반환
int GetIdlePlayer(int client)
{
    if (!IsFakeClient(client))
    {
        return 0;
    }
    int idlePlayer = L4D_GetIdlePlayerOfBot(client);
    return IsClient(idlePlayer) ? idlePlayer : 0;
}

bool IsValidAliveClient(int client)
{
    return (IsClient(client) && IsClientInGame(client) && IsPlayerAlive(client));
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
