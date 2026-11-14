#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <hxlib>

#define WARNING_SOUND "ui/beepclear.wav"

bool   g_bPluginStarted;

ConVar g_hConVarThreshold;

// 탄약 종류별로 이미 알렸는지 기억해서 부족한 동안 재장전할 때마다 다시 알리지 않는다
bool   g_bLowAmmo[MAXPLAYERS_L4D2 + 1][Ammo_MAX];

public Plugin myinfo =
{
    name        = "L4D2 Low Ammo Notifier",
    author      = "Rainy",
    description = "예비 탄약이 부족해지면 소리와 채팅으로 알립니다.",
    version     = "1.0.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_low_ammo_notifier"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_low_ammo_notifier.phrases");

    g_hConVarThreshold = CreateConVar(
        "l4d2_low_ammo_notifier_threshold", "2.0",
        "when reserve ammo is less than or equal to this * ClipSize, consider it as low ammo.",
        FCVAR_NOTIFY, true, 0.0);
    AutoExecConfig(true, "l4d2_low_ammo_notifier");
}

// 늦게 로드된 경우에도 OnPluginStart 직후에 불린다
public void OnAllPluginsLoaded()
{
    if (!g_bPluginStarted && LibraryExists(HXLIB_LIBRARY))
        StartPlugin();
}

public void OnLibraryAdded(const char[] name)
{
    if (!g_bPluginStarted && strcmp(name, HXLIB_LIBRARY) == 0)
        StartPlugin();
}

public void OnLibraryRemoved(const char[] name)
{
    if (strcmp(name, HXLIB_LIBRARY) == 0)
        g_bPluginStarted = false;
}

public void OnMapStart()
{
    PrecacheSound(WARNING_SOUND);
}

public void OnClientPutInServer(int client)
{
    if (g_bPluginStarted && !IsFakeClient(client))
        HookClient(client);
}

void StartPlugin()
{
    g_bPluginStarted = true;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            HookClient(i);
    }
}

void HookClient(int client)
{
    for (int i = 0; i < sizeof(g_bLowAmmo[]); i++)
        g_bLowAmmo[client][i] = false;

    AddEntityHook(client, EntityHook_RemoveAmmo, EHook_Post, EntityHook_RemoveAmmoPost);
}

void EntityHook_RemoveAmmoPost(int client, int amount, AmmoType ammoType, bool handled)
{
    if (handled
        || amount <= 0
        || ammoType <= Ammo_None
        || ammoType >= Ammo_MAX
        || IsAmmoTypeInfinite(ammoType)
        || GetClientTeam(client) != Team_Survivor)
    {
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, WeaponSlot_Primary);
    if (weapon == -1 || GetAmmoType(weapon) != ammoType)
        return;

    int magazineMax = GetMaxMagazineAmmo(weapon);
    if (magazineMax <= 0)
        return;

    int  reserve                 = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
    bool low                     = reserve <= RoundToFloor(float(magazineMax) * g_hConVarThreshold.FloatValue);
    bool wasLow                  = g_bLowAmmo[client][ammoType];
    g_bLowAmmo[client][ammoType] = low;

    // 차감 시점에 탄창이 이미 채워졌는지 알 수 없어, 전체 탄약은 다음 프레임에 읽는다
    if (low && !wasLow)
        RequestFrame(Frame_Notify, GetClientUserId(client));
}

void Frame_Notify(int userid)
{
    int client = GetClientOfUserId(userid);
    if (!client || !IsClientInGame(client))
        return;

    int weapon = GetPlayerWeaponSlot(client, WeaponSlot_Primary);
    if (weapon == -1)
        return;

    int total = GetEntProp(weapon, Prop_Send, "m_iClip1")
              + GetEntProp(client, Prop_Send, "m_iAmmo", _, GetAmmoType(weapon));

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == Team_Infected)
            continue;

        EmitSoundToClient(i, WARNING_SOUND, _, SNDCHAN_STATIC);
        CPrintToChat(i, "%t", "Low Ammo", client, total);
    }
}
