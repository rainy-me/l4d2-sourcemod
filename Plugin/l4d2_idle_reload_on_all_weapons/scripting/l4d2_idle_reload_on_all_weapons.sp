#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define RELOAD_TIMEOUT   2.5
#define MAX_WEAPON_SLOTS 5

public Plugin myinfo =
{
    name        = "L4D2 Idle Reload On All Weapons",
    author      = "Rainy",
    description = "모든 무기에서 유휴 장전이 가능하도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_reload_on_all_weapons"
};

Handle    g_hFinishReload                        = null;
StringMap g_smIdleReloadableWeapons              = null;
int       g_iReloadingWeaponSlot[MAXPLAYERS + 1] = { -1, ... };

enum EventState
{
    State_None,
    State_Event1_Done,
};
EventState g_PlayerState[MAXPLAYERS + 1]   = { State_None, ... };
float      g_fStateTimeout[MAXPLAYERS + 1] = { 0.0, ... };

public void OnPluginStart()
{
    Handle hGameConf = LoadGameConfigFile("l4d2_idle_reload_on_all_weapons");
    if (hGameConf == null)
    {
        SetFailState("Failed to load game config file: l4d2_idle_reload_on_all_weapons.txt");
    }

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::FinishReload");
    g_hFinishReload = EndPrepSDKCall();
    delete hGameConf;
    if (g_hFinishReload == null)
    {
        SetFailState("Failed to find CBaseCombatWeapon::FinishReload");
    }

    // 유휴 재장전 가능한 무기 목록 초기화
    InitializeIdleReloadableWeapons();

    // 2단계 이벤트
    HookEvent("weapon_reload", Event_WeaponReload);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    // 예외 처리
    HookEvent("player_death", Event_ResetPlayerState);
    HookEvent("player_team", Event_ResetPlayerState);
    HookEvent("item_pickup", Event_ResetPlayerState);
    HookEvent("golden_crowbar_pickup", Event_ResetPlayerState);
    HookEvent("round_end", Event_ResetPlayerState);
    HookEvent("give_weapon", Event_ResetPlayerState);
    HookEvent("upgrade_pack_used", Event_ResetPlayerState);
    HookEvent("weapon_drop", Event_ResetPlayerState);
    HookEvent("weapon_pickup", Event_ResetPlayerState);
    HookEvent("player_connect", Event_ResetPlayerState);
    HookEvent("player_disconnect", Event_ResetPlayerState);
}

public void OnPluginEnd()
{
    delete g_hFinishReload;
    delete g_smIdleReloadableWeapons;
}

void InitializeIdleReloadableWeapons()
{
    g_smIdleReloadableWeapons = new StringMap();

    g_smIdleReloadableWeapons.SetValue("weapon_pistol", true);
    g_smIdleReloadableWeapons.SetValue("weapon_pistol_magnum", true);
    g_smIdleReloadableWeapons.SetValue("weapon_smg", true);
    g_smIdleReloadableWeapons.SetValue("weapon_smg_silenced", true);
    g_smIdleReloadableWeapons.SetValue("weapon_smg_mp5", true);
}

public void Event_WeaponReload(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    int activeWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
    {
        return;
    }

    for (int i = 0; i <= MAX_WEAPON_SLOTS; i++)
    {
        int weaponInSlot = GetPlayerWeaponSlot(client, i);
        if (weaponInSlot == activeWeapon)
        {
            g_iReloadingWeaponSlot[client] = i;
            break;
        }
    }

    // 1번째 이벤트: 상태를 1단계 완료로 설정하고 타임아웃 시작
    g_PlayerState[client]   = State_Event1_Done;
    g_fStateTimeout[client] = GetGameTime() + RELOAD_TIMEOUT;
}

public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    // 이전 상태가 1단계 완료이고, 타임아웃되지 않았는지 확인
    if (g_PlayerState[client] == State_Event1_Done && GetGameTime() < g_fStateTimeout[client])
    {
        IdleReload(client);
    }

    ResetPlayerState(client);
}

public void Event_ResetPlayerState(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ResetPlayerState(client);
    }
}

void ResetPlayerState(int client)
{
    g_PlayerState[client]          = State_None;
    g_fStateTimeout[client]        = 0.0;
    g_iReloadingWeaponSlot[client] = -1;
}

void IdleReload(int client)
{
    // 0번(주무기), 1번(보조무기) 슬롯 외에는 무시
    if (g_iReloadingWeaponSlot[client] != 0 && g_iReloadingWeaponSlot[client] != 1)
    {
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, g_iReloadingWeaponSlot[client]);
    if (!IsValidEntity(weapon))
    {
        return;
    }

    char active_weapon_clsname[64];
    GetEntityClassname(weapon, active_weapon_clsname, sizeof(active_weapon_clsname));
    if (!IsIdleReloadableWeapon(active_weapon_clsname))
    {
        return;
    }

    SDKCall(g_hFinishReload, weapon);
    // PrintToChatAll("유휴 재장전!");
}

/**
 * 무기가 유휴 재장전 가능한지 확인
 *
 * @param weapon_clsname 무기 클래스 이름
 * @return 유휴 재장전 가능 여부
 */
bool IsIdleReloadableWeapon(const char[] weapon_clsname)
{
    bool dummy;
    return g_smIdleReloadableWeapons.GetValue(weapon_clsname, dummy);
}