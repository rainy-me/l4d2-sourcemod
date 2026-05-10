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
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_idle_reload_on_all_weapons"
};

Handle    g_hFinishReload           = null;
StringMap g_smIdleReloadableWeapons = null;

enum EventState
{
    State_None,
    State_Event1_Done,
};
int        g_iActiveWeapon[MAXPLAYERS + 1]        = { -1, ... };
int        g_iReloadingWeaponSlot[MAXPLAYERS + 1] = { -1, ... };
EventState g_esEventState[MAXPLAYERS + 1]         = { State_None, ... };
float      g_fStateTimeout[MAXPLAYERS + 1]        = { 0.0, ... };

public void OnPluginStart()
{
    GameData hGameConf = LoadGameConfigFile("l4d2_idle_reload_on_all_weapons");
    if (hGameConf == null)
    {
        SetFailState("Failed to load game config file: l4d2_idle_reload_on_all_weapons.txt");
    }

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::FinishReload");
    g_hFinishReload = EndPrepSDKCall();
    if (g_hFinishReload == null)
    {
        SetFailState("Failed to find CBaseCombatWeapon::FinishReload");
    }
    delete hGameConf;

    // 유휴 재장전 가능한 무기 목록 초기화
    InitializeIdleReloadableWeapons();

    // 2단계 이벤트
    HookEvent("weapon_reload", Event_WeaponReload);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    // 예외 처리
    HookEvent("round_end", Event_ResetStateAll);
    HookEvent("player_death", Event_ResetState);
    HookEvent("give_weapon", Event_ResetState);
    HookEvent("upgrade_pack_used", Event_ResetState);
    HookEvent("weapon_drop", Event_ResetState);
}

void Event_ResetState(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsClient(client))
    {
        ResetState(client);
    }
}

void Event_ResetStateAll(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClient(i) && IsClientInGame(i))
        {
            ResetState(i);
        }
    }
}

void Event_WeaponReload(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    // 현재 활성화된 무기 가져오기
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
    {
        return;
    }

    // 현재 활성화된 무기의 슬롯 찾기
    int activeWeaponSlot = -1;
    for (int i = 0; i < MAX_WEAPON_SLOTS; i++)
    {
        if (GetPlayerWeaponSlot(client, i) == activeWeapon)
        {
            activeWeaponSlot = i;
            break;
        }
    }

    // 0번(주무기), 1번(보조무기) 슬롯인지 확인
    if (activeWeaponSlot != 0 && activeWeaponSlot != 1)
    {
        return;
    }

    // 무기가 유휴 재장전 가능한지 확인
    char activeWeaponClsname[64];
    GetEntityClassname(activeWeapon, activeWeaponClsname, sizeof(activeWeaponClsname));
    if (!IsIdleReloadableWeapon(activeWeaponClsname))
    {
        return;
    }

    // 현재 활성화된 무기 및 슬롯 저장
    g_iActiveWeapon[client]        = activeWeapon;
    g_iReloadingWeaponSlot[client] = activeWeaponSlot;

    // 이벤트: 상태를 1단계 완료로 설정하고 타임아웃 시작
    g_esEventState[client]         = State_Event1_Done;
    g_fStateTimeout[client]        = GetGameTime() + RELOAD_TIMEOUT;
}

void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (!IsClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        ResetState(client);
        return;
    }

    // 이전 상태가 1단계 완료이고, 타임아웃되지 않았는지 확인
    if (g_esEventState[client] != State_Event1_Done || g_fStateTimeout[client] < GetGameTime())
    {
        ResetState(client);
        return;
    }

    // 저장된 무기와 현재 재장전할 슬롯의 무기가 일치하는지 확인
    if (g_iActiveWeapon[client] != GetPlayerWeaponSlot(client, g_iReloadingWeaponSlot[client]))
    {
        ResetState(client);
        return;
    }

    IdleReload(g_iActiveWeapon[client]);
    ResetState(client);
}

void IdleReload(int weapon)
{
    if (IsValidEntity(weapon))
    {
        SDKCall(g_hFinishReload, weapon);
    }
}

void ResetState(int client)
{
    g_iActiveWeapon[client]        = -1;
    g_iReloadingWeaponSlot[client] = -1;
    g_esEventState[client]         = State_None;
    g_fStateTimeout[client]        = 0.0;
}

bool IsIdleReloadableWeapon(const char[] weaponClsname)
{
    bool dummy;
    return g_smIdleReloadableWeapons.GetValue(weaponClsname, dummy);
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

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}
