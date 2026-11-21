#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <multicolors>

#define ADMINS_FILE "ems/admin system/admins.txt"
#define MIN_LEVEL   2
#define MAX_LEVEL   28
#define SI_COUNT    6

enum
{
    CMD_HARD,
    CMD_LIMIT,
    CMD_RESPAWN
};

// 디렉터가 묻는 키는 이름 + "Limit" (HunterLimit)
static const char g_sNames[SI_COUNT][] = { "Boomer", "Charger", "Hunter", "Jockey", "Smoker", "Spitter" };

ConVar g_hConVarGameMode;
bool   g_bAllowed;             // coop, realism에서만 동작한다
char   g_sGameMode[32];
char   g_sPath[PLATFORM_MAX_PATH];
int    g_iLevel;               // 0이면 꺼짐
int    g_iLimits[SI_COUNT];    // -1이면 GetBaseLimit() 값
int    g_iRespawn;             // 0이면 레벨 기준 기본값 (6 이하 20, 7 이상 15)

public Plugin myinfo =
{
    name        = "L4D2 Hard X System",
    author      = "Rainy",
    description = "특수 감염자의 수와 리스폰 간격을 레벨로 조절합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_hard_x_system"
};

public void OnPluginStart()
{
    g_hConVarGameMode = FindConVar("mp_gamemode");
    g_hConVarGameMode.AddChangeHook(ConVarChanged_GameMode);
    ReadGameMode();

    LoadTranslations("l4d2_hard_x_system.phrases");

    BuildPath(Path_SM, g_sPath, sizeof(g_sPath), "data/l4d2_hard_x_system.cfg");
    LoadSettings();

    RegConsoleCmd("sm_hard", Cmd_Hard, "Set the hard level.");
    RegConsoleCmd("sm_hardl", Cmd_Limit, "Set the limit of special infected.");
    RegConsoleCmd("sm_hardr", Cmd_Respawn, "Set the special infected respawn interval.");
}

void ConVarChanged_GameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ReadGameMode();
}

void ReadGameMode()
{
    g_hConVarGameMode.GetString(g_sGameMode, sizeof(g_sGameMode));
    for (int i = 0; g_sGameMode[i] != '\0'; i++)
        g_sGameMode[i] = CharToLower(g_sGameMode[i]);

    g_bAllowed     = StrEqual(g_sGameMode, "coop") || StrEqual(g_sGameMode, "realism");
    g_sGameMode[0] = CharToUpper(g_sGameMode[0]);
}

void LoadSettings()
{
    ResetLimits();

    KeyValues kv = new KeyValues("HardXSystem");
    if (kv.ImportFromFile(g_sPath))
    {
        int level = kv.GetNum("level");
        if (IsValidLevel(level))
            g_iLevel = level;

        int respawn = kv.GetNum("respawn");
        if (respawn >= 1)
            g_iRespawn = respawn;

        for (int i = 0; i < SI_COUNT; i++)
        {
            int limit = kv.GetNum(g_sNames[i], -1);
            if (limit >= 0 && limit <= MAX_LEVEL)
                g_iLimits[i] = limit;
        }
    }
    delete kv;
}

void SaveSettings()
{
    KeyValues kv = new KeyValues("HardXSystem");
    kv.SetNum("level", g_iLevel);
    if (g_iRespawn != 0)
        kv.SetNum("respawn", g_iRespawn);

    for (int i = 0; i < SI_COUNT; i++)
    {
        if (g_iLimits[i] != -1)
            kv.SetNum(g_sNames[i], g_iLimits[i]);
    }
    kv.ExportToFile(g_sPath);
    delete kv;
}

void ResetLimits()
{
    for (int i = 0; i < SI_COUNT; i++)
        g_iLimits[i] = -1;
}

// 디렉터는 일반 coop에서도 cm_ 키를 먼저 묻고, 값이 -1이면 cm_ 없는 키로 넘어간다.
// 맵 스크립트의 종류별 Limit이 cm_BaseSpecialLimit을 덮어쓰는 버그 때문에 종류별 Limit도 함께 응답한다.
// https://github.com/Tsuey/L4D2-Community-Update/issues/317
public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
    if (g_iLevel == 0 || !g_bAllowed)
        return Plugin_Continue;

    if (StrEqual(key, "cm_MaxSpecials") || StrEqual(key, "DominatorLimit"))
    {
        retVal = g_iLevel;
    }
    else if (StrEqual(key, "cm_BaseSpecialLimit"))
    {
        retVal = GetBaseLimit();
    }
    else
    {
        int index = FindLimitKey(key);
        if (index == -1)
            return Plugin_Continue;

        retVal = GetLimit(index);
    }
    return Plugin_Handled;
}

public Action L4D_OnGetScriptValueFloat(const char[] key, float &retVal)
{
    if (g_iLevel == 0 || !g_bAllowed || !StrEqual(key, "cm_SpecialRespawnInterval"))
        return Plugin_Continue;

    retVal = float(GetRespawnInterval());
    return Plugin_Handled;
}

int FindLimitKey(const char[] key)
{
    for (int i = 0; i < SI_COUNT; i++)
    {
        int len = strlen(g_sNames[i]);
        if (strncmp(key, g_sNames[i], len) == 0 && StrEqual(key[len], "Limit"))
            return i;
    }
    return -1;
}

int GetBaseLimit()
{
    if (g_iLevel <= 4)
        return 1;
    if (g_iLevel <= 10)
        return 2;
    if (g_iLevel <= 15)
        return 3;
    if (g_iLevel <= 22)
        return 4;
    return 5;
}

int GetLimit(int index)
{
    return g_iLimits[index] != -1 ? g_iLimits[index] : GetBaseLimit();
}

int GetRespawnInterval()
{
    if (g_iRespawn != 0)
        return g_iRespawn;
    return g_iLevel <= 6 ? 20 : 15;
}

bool HasCustomLimits()
{
    for (int i = 0; i < SI_COUNT; i++)
    {
        if (g_iLimits[i] != -1)
            return true;
    }
    return false;
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    if (g_bAllowed)
        CreateTimer(0.5, Timer_PrintActivation, _, TIMER_FLAG_NO_MAPCHANGE);
}

void Timer_PrintActivation(Handle timer)
{
    PrintActivation();
}

Action Cmd_Hard(int client, int args)
{
    return HandleCommand(client, args, CMD_HARD);
}

Action Cmd_Limit(int client, int args)
{
    return HandleCommand(client, args, CMD_LIMIT);
}

Action Cmd_Respawn(int client, int args)
{
    return HandleCommand(client, args, CMD_RESPAWN);
}

Action HandleCommand(int client, int args, int type)
{
    if (!g_bAllowed)
        return Plugin_Handled;

    // 꺼져 있으면 !hard 말고는 상태만 알려준다
    if (g_iLevel == 0 && type != CMD_HARD)
    {
        PrintInfo();
        return Plugin_Handled;
    }

    // 인자가 없으면 조회. 조회는 관리자가 아니어도 된다
    if (args == 0)
    {
        if (type == CMD_HARD)
            PrintInfo();
        else if (type == CMD_LIMIT)
            PrintLimits();
        else
            PrintRespawn();
        return Plugin_Handled;
    }

    if (!CheckCommandAccess(client, "sm_hard_set", ADMFLAG_ROOT) && !IsListedInAdminsTxt(client))
    {
        CReplyToCommand(client, "%t", "Admin Only");
        return Plugin_Handled;
    }

    if (type == CMD_HARD)
        OnHardCommand(client, args);
    else if (type == CMD_LIMIT)
        OnLimitCommand(client, args);
    else
        OnRespawnCommand(client, args);
    return Plugin_Handled;
}

void OnHardCommand(int client, int args)
{
    char arg[16];
    int  level;
    GetCmdArg(1, arg, sizeof(arg));
    if (args != 1 || !ParseInt(arg, level) || !IsValidLevel(level))
    {
        CReplyToCommand(client, "%t", "Hard Usage", MIN_LEVEL, MAX_LEVEL);
        return;
    }

    g_iLevel = level;
    if (level == 0)
    {
        // 끌 때는 커스텀 제한도 전부 초기화
        ResetLimits();
        g_iRespawn = 0;
        CPrintToChatAll("%t", "Hard Off Reset");
    }
    else
    {
        PrintInfo();
        if (level == MAX_LEVEL)
            CPrintToChatAll("%t", "Max Level Warning", level);
    }
    SaveSettings();
}

void OnLimitCommand(int client, int args)
{
    char names[64], value[16];
    GetCmdArg(1, names, sizeof(names));
    GetCmdArg(2, value, sizeof(value));

    // limit이 -1이면 기본값으로 되돌린다
    int  mask, limit = -1;
    bool ok;
    if (args == 1 && StrEqual(names, "reset", false))
    {
        mask = (1 << SI_COUNT) - 1;
        ok   = true;
    }
    else if (args == 2)
    {
        mask = ParseNames(names);
        ok   = mask != 0 && (StrEqual(value, "reset", false) || (ParseInt(value, limit) && limit >= 0 && limit <= MAX_LEVEL));
    }

    if (!ok)
    {
        CReplyToCommand(client, "%t", "Limit Usage", MAX_LEVEL);
        return;
    }

    for (int i = 0; i < SI_COUNT; i++)
    {
        if (mask & (1 << i))
            g_iLimits[i] = limit;
    }
    PrintLimits();
    SaveSettings();
}

void OnRespawnCommand(int client, int args)
{
    char arg[16];
    int  seconds;
    GetCmdArg(1, arg, sizeof(arg));
    if (args == 1 && StrEqual(arg, "reset", false))
    {
        seconds = 0;
    }
    else if (args != 1 || !ParseInt(arg, seconds) || seconds < 1)
    {
        CReplyToCommand(client, "%t", "Respawn Usage");
        return;
    }

    g_iRespawn = seconds;
    PrintRespawn();
    SaveSettings();
}

// "a,b,c" -> 종류 비트마스크. 모르는 이름이 하나라도 있으면 0
int ParseNames(const char[] text)
{
    char parts[SI_COUNT][16];
    int  count = ExplodeString(text, ",", parts, sizeof(parts), sizeof(parts[]), true);
    int  mask;
    for (int i = 0; i < count; i++)
    {
        int index = -1;
        for (int j = 0; j < SI_COUNT; j++)
        {
            if (StrEqual(parts[i], g_sNames[j], false))
                index = j;
        }
        if (index == -1)
            return 0;

        mask |= 1 << index;
    }
    return mask;
}

void PrintInfo()
{
    if (g_iLevel == 0)
    {
        CPrintToChatAll("%t", "Hard Off");
        return;
    }

    PrintActivation();
    if (HasCustomLimits())
        PrintLimits();
}

void PrintActivation()
{
    if (g_iLevel == 0)
        return;

    // 덧붙는 문구도 받는 사람의 언어로 만들어야 해서 한 명씩 보낸다
    char limits[64], respawn[64];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

        limits[0]  = '\0';
        respawn[0] = '\0';
        if (HasCustomLimits())
            FormatEx(limits, sizeof(limits), "%T", "Custom Limits", i);
        if (g_iRespawn != 0)
            FormatEx(respawn, sizeof(respawn), "%T", "Custom Respawn", i, g_iRespawn);

        CPrintToChat(i, "%t", "Activation", g_sGameMode, g_iLevel, limits, respawn);
    }
}

void PrintLimits()
{
    char text[256];
    int  total;
    for (int i = 0; i < SI_COUNT; i++)
    {
        Format(text, sizeof(text), "%s%s%s %s%d", text, i == 0 ? "" : "{default}, ", g_sNames[i],
               g_iLimits[i] != -1 ? "{lightgreen}" : "{olive}", GetLimit(i));
        total += GetLimit(i);
    }
    CPrintToChatAll("%s", text);

    if (total < g_iLevel)
        CPrintToChatAll("%t", "Slots Warning", total, g_iLevel);
}

void PrintRespawn()
{
    CPrintToChatAll("%t", g_iRespawn == 0 ? "Respawn Interval Default" : "Respawn Interval", GetRespawnInterval());
}

bool IsListedInAdminsTxt(int client)
{
    char auth[32];
    if (client == 0 || !GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
        return false;

    File file = OpenFile(ADMINS_FILE, "r");
    if (file == null)
        return false;

    char line[256];
    bool found;
    while (!found && file.ReadLine(line, sizeof(line)))
    {
        int comment = StrContains(line, "//");
        if (comment != -1)
            line[comment] = '\0';
        // UTF-8 BOM이 있으면 첫 줄 관리자가 인식되지 않으므로 떼어낸다
        ReplaceString(line, sizeof(line), "\xEF\xBB\xBF", "");
        TrimString(line);
        // GetClientAuthId는 STEAM_1 형식을 반환하므로 STEAM_0 표기를 맞춰줌
        ReplaceString(line, sizeof(line), "STEAM_0", "STEAM_1");
        found = line[0] != '\0' && StrEqual(line, auth);
    }
    delete file;
    return found;
}

bool IsValidLevel(int level)
{
    return level == 0 || (level >= MIN_LEVEL && level <= MAX_LEVEL);
}

bool ParseInt(const char[] text, int &value)
{
    return text[0] != '\0' && StringToIntEx(text, value) == strlen(text);
}
