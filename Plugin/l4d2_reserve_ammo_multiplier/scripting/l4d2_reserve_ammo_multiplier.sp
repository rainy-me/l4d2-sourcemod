#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>

#define STORED_FILE        "l4d2_reserve_ammo_multiplier.txt"
#define AMMO_COUNT         6
#define DEFAULT_MULTIPLIER 1.0
#define MIN_MULTIPLIER     1.0
#define MAX_MULTIPLIER     5.0

// m_iAmmo offsets for each gun category
// Index -> cvar name mapping
static const char g_sCvarAmmoGunList[AMMO_COUNT][] = {
    "ammo_smg_max",
    "ammo_shotgun_max",
    "ammo_autoshotgun_max",
    "ammo_huntingrifle_max",
    "ammo_sniperrifle_max",
    "ammo_assaultrifle_max"
};

static const int g_iCvarAmmoGunDefault[AMMO_COUNT] = {
    650,    // smg
    72,     // shotgun
    90,     // autoshotgun
    150,    // huntingrifle
    180,    // sniperrifle
    360     // assaultrifle
};

ConVar g_hAmmoCvars[AMMO_COUNT];
int    g_iPreAmmoStored[AMMO_COUNT];
int    g_iAmmoStored[AMMO_COUNT];

public Plugin myinfo =
{
    name        = "L4D2 Reserve Ammo Multiplier",
    author      = "Rainy",
    description = "예비 탄약 소지량을 배율로 조정합니다.",
    version     = "1.2.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_reserve_ammo_multiplier"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_reserve_ammo_multiplier.phrases");

    // Init cvars and store defaults
    for (int i = 0; i < AMMO_COUNT; i++)
    {
        g_hAmmoCvars[i]     = FindConVar(g_sCvarAmmoGunList[i]);
        g_iPreAmmoStored[i] = g_iCvarAmmoGunDefault[i];
        g_iAmmoStored[i]    = g_iCvarAmmoGunDefault[i];
    }

    HookEvent("round_freeze_end", Event_RoundFreezeEnd);

    RegAdminCmd("sm_amm", Cmd_AmmoMultiplier, ADMFLAG_ROOT);
    RegConsoleCmd("sm_ammi", Cmd_PrintInfo);
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    float multiplier = DEFAULT_MULTIPLIER;
    if (!ReadMultiplierFromFile(multiplier))
    {
        for (int i = 0; i < AMMO_COUNT; i++)
        {
            SetCvarAmmo(i, g_iCvarAmmoGunDefault[i]);
        }
        WriteMultiplierToFile(multiplier);
        return;
    }

    if (multiplier > DEFAULT_MULTIPLIER)
    {
        for (int i = 0; i < AMMO_COUNT; i++)
        {
            SetCvarAmmo(i, RoundFloat(float(g_iCvarAmmoGunDefault[i]) * multiplier));
        }
        CPrintToChatAll("%t", "Ammo Setting Load", multiplier);
    }
}

Action Cmd_PrintInfo(int client, int args)
{
    float multiplier = DEFAULT_MULTIPLIER;
    if (ReadMultiplierFromFile(multiplier))
    {
        CPrintToChatAll("%t", "Current Multiplier", multiplier);
    }
    return Plugin_Handled;
}

Action Cmd_AmmoMultiplier(int client, int args)
{
    if (args != 1)
    {
        CReplyToCommand(client, "%t", "Help");
        return Plugin_Handled;
    }

    char sArg[8];
    GetCmdArg(1, sArg, sizeof(sArg));
    if (!IsCharNumeric(sArg[0]))
    {
        CReplyToCommand(client, "%t", "Invalid Value");
        return Plugin_Handled;
    }

    float multiplier = ClampFloat(StringToFloat(sArg), MIN_MULTIPLIER, MAX_MULTIPLIER);

    for (int i = 0; i < AMMO_COUNT; i++)
    {
        SetCvarAmmo(i, RoundFloat(float(g_iCvarAmmoGunDefault[i]) * multiplier));
    }
    WriteMultiplierToFile(multiplier);
    ReCalculateReserveAmmo();

    if (multiplier == DEFAULT_MULTIPLIER)
    {
        CPrintToChatAll("%t", "Ammo Reset");
    }
    else
    {
        CPrintToChatAll("%t", "Ammo Setting", multiplier);
    }
    return Plugin_Handled;
}

// ==========================================================================
// AMMO / CVAR MANAGEMENT
// ==========================================================================

void SetCvarAmmo(int idx, int value)
{
    int intAbs            = (value < 0) ? -value : value;
    g_iPreAmmoStored[idx] = g_iAmmoStored[idx];
    g_iAmmoStored[idx]    = intAbs;

    if (g_hAmmoCvars[idx] != null)
    {
        int flags                  = g_hAmmoCvars[idx].Flags;
        g_hAmmoCvars[idx].Flags    = flags & ~FCVAR_NOTIFY;
        g_hAmmoCvars[idx].IntValue = intAbs;
        g_hAmmoCvars[idx].Flags    = flags;
    }
}

void ReCalculateReserveAmmo()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
        {
            continue;
        }

        int weapon = GetPlayerWeaponSlot(client, 0);    // slot0 = primary
        if (weapon == -1 || !IsValidEntity(weapon))
        {
            continue;
        }

        int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
        int idx      = GetIdxByAmmoType(ammoType);
        if (idx == -1)
        {
            continue;
        }

        int currentAmmo = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
        int newAmmo     = ReCalcReserveAmmoByCvarIdx(currentAmmo, idx);
        GivePlayerItem(client, "Ammo");
        SetEntProp(client, Prop_Send, "m_iAmmo", newAmmo, _, ammoType);
    }
}

int GetIdxByAmmoType(int ammoType)
{
    switch (ammoType)
    {
        case 5: return 0;     // smg
        case 7: return 1;     // shotgun
        case 8: return 2;     // autoshotgun
        case 9: return 3;     // huntingrifle
        case 10: return 4;    // sniperrifle
        case 3: return 5;     // assaultrifle
    }
    return -1;
}

int ReCalcReserveAmmoByCvarIdx(int currentAmmo, int idx)
{
    if (g_iPreAmmoStored[idx] > 0)
    {
        float ratio = float(currentAmmo) / float(g_iPreAmmoStored[idx]);
        return RoundFloat(float(g_iAmmoStored[idx]) * ratio);
    }
    return 0;
}

// ==========================================================================
// FILE I/O
// ==========================================================================

bool WriteMultiplierToFile(float multiplier)
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/%s", STORED_FILE);
    File file = OpenFile(sPath, "w");
    if (file == null)
    {
        LogError("Failed to open %s for writing", sPath);
        return false;
    }
    if (!file.WriteLine("%.2f", multiplier))
    {
        LogError("Failed to write to %s", sPath);
        delete file;
        return false;
    }
    delete file;
    return true;
}

bool ReadMultiplierFromFile(float &multiplier)
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/%s", STORED_FILE);
    if (!FileExists(sPath))
    {
        return false;
    }

    File file = OpenFile(sPath, "r");
    if (file == null)
    {
        LogError("Failed to open %s for reading", sPath);
        return false;
    }

    char buffer[8];
    if (!file.ReadLine(buffer, sizeof(buffer)))
    {
        LogError("Failed to read from %s", sPath);
        delete file;
        return false;
    }
    delete file;
    TrimString(buffer);

    float value = StringToFloat(buffer);
    if (value < MIN_MULTIPLIER || value > MAX_MULTIPLIER)
    {
        LogError("Invalid value in %s: %s", sPath, buffer);
        return false;
    }

    multiplier = ClampFloat(value, MIN_MULTIPLIER, MAX_MULTIPLIER);
    return true;
}

// ==========================================================================
// HELPERS
// ==========================================================================

float ClampFloat(float input, float min, float max)
{
    if (input < min)
        return min;
    if (input > max)
        return max;
    return input;
}
