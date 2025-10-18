#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Idle Reload On All Weapons",
    author      = "Rainy",
    description = "모든 무기에서 유휴 장전이 가능하도록 합니다.",
    version     = "1.0.0",
    url         = ""
};

Handle g_hFinishReload                        = null;
int    g_iActiveWeapon[MAXPLAYERS + 1]        = { -1, ... };
int    g_iReloadingWeaponSlot[MAXPLAYERS + 1] = { -1, ... };

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

    HookEvent("weapon_reload", Event_WeaponReload);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);
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

    for (int i = 0; i <= 5; i++)
    {
        int weaponInSlot = GetPlayerWeaponSlot(client, i);
        if (weaponInSlot == activeWeapon)
        {
            g_iActiveWeapon[client]        = activeWeapon;
            g_iReloadingWeaponSlot[client] = i;
            break;
        }
    }

    // 1번째 이벤트: 상태를 1단계 완료로 설정하고 타임아웃 시작
    g_PlayerState[client]   = State_Event1_Done;
    g_fStateTimeout[client] = GetGameTime() + 3.0;    // 3초 제한
}

public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("player"));
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    // 이전 상태가 1단계이고, 타임아웃되지 않았는지 확인
    if (g_PlayerState[client] == State_Event1_Done && GetGameTime() < g_fStateTimeout[client])
    {
        IdleReload(client);
    }

    g_PlayerState[client] = State_None;
}

public void IdleReload(int client)
{
    if (g_iReloadingWeaponSlot[client] != 0 && g_iReloadingWeaponSlot[client] != 1)
    {
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, g_iReloadingWeaponSlot[client]);
    if (!IsValidEntity(weapon) || weapon != g_iActiveWeapon[client])
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
    // PrintToChatAll("즉시 재장전!");
}

// 목록에 있는 무기만 유휴 재장전 실행
bool IsIdleReloadableWeapon(char[] weapon_clsname)
{
    if (StrEqual(weapon_clsname, "weapon_pistol")) return true;
    if (StrEqual(weapon_clsname, "weapon_pistol_magnum")) return true;
    if (StrEqual(weapon_clsname, "weapon_smg")) return true;
    if (StrEqual(weapon_clsname, "weapon_smg_silenced")) return true;
    if (StrEqual(weapon_clsname, "weapon_smg_mp5")) return true;
    return false;
}