#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define DAY_SECONDS            86400
#define LONG_ABSENCE_SECONDS   (DAY_SECONDS * 10)    // 10일
#define REGULAR_VISITS         10                    // 이 횟수 이상이면 단골
#define SESSION_RESUME_SECONDS 60 * 5                // 퇴장 후 이 시간 이내 재접속은 같은 세션(챕터 전환 등)으로 간주
#define GREET_DELAY            4.0                   // 접속 후 인사 메시지를 띄우기까지의 지연(초)

// 인사 종류
#define GREET_NEW              0
#define GREET_LONG             1
#define GREET_REGULAR          2
#define GREET_NORMAL           3

// 인사 종류별 번역키 (GREET_* 순서와 일치해야 함)
char g_sGreetPhrases[][] = {
    "First Greeting",
    "Long Absence Greeting",
    "Regular Greeting",
    "Greeting an Acquaintance"
};

Database g_hDB = null;
char     g_sSteamID[MAXPLAYERS + 1][32];
int      g_iJoinTime[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "L4D2 Welcome",
    author      = "Rainy",
    description = "환영 인사와 서버 안내를 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_welcome"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_welcome.phrases");

    char error[256];
    g_hDB = SQLite_UseDatabase("l4d2_welcome", error, sizeof(error));
    if (g_hDB == null)
    {
        SetFailState("SQLite failed: %s", error);
        return;
    }

    SQL_FastQuery(g_hDB, "CREATE TABLE IF NOT EXISTS visitors (" ... "steamid TEXT PRIMARY KEY, " ... "first_seen INTEGER, " ... "last_seen INTEGER, " ... "visits INTEGER, " ... "play_time INTEGER DEFAULT 0)");
}

public void OnClientDisconnect(int client)
{
    // 이번 세션 플레이 시간을 누적하고 퇴장 시각을 기록 (인증된 클라이언트만)
    // last_seen을 '퇴장 시각'으로 두면 다음 접속 시 (now - last_seen)이 '서버를 비운 시간'이 되어
    // 챕터 전환(짧은 재접속)과 진짜 재방문을 구분할 수 있다.
    if (g_iJoinTime[client] > 0 && g_sSteamID[client][0] != '\0')
    {
        int now    = GetTime();
        int played = now - g_iJoinTime[client];
        if (played > 0)
        {
            char safeId[64];
            SQL_EscapeString(g_hDB, g_sSteamID[client], safeId, sizeof(safeId));

            char query[256];
            Format(query, sizeof(query),
                   "UPDATE visitors SET play_time = play_time + %d, last_seen = %d WHERE steamid = '%s'", played, now, safeId);
            SQL_TQuery(g_hDB, OnUpdateDone, query);
        }
    }

    g_iJoinTime[client] = 0;
    g_sSteamID[client]  = "";
}

public void OnClientPostAdminCheck(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    if (!GetClientAuthId(client, AuthId_Steam2, g_sSteamID[client], sizeof(g_sSteamID[])))
    {
        LogError("GetClientAuthId failed");
        return;
    }

    g_iJoinTime[client] = GetTime();

    char safeId[64];
    SQL_EscapeString(g_hDB, g_sSteamID[client], safeId, sizeof(safeId));

    char query[256];
    Format(query, sizeof(query), "SELECT visits, last_seen, play_time FROM visitors WHERE steamid = '%s'", safeId);
    SQL_TQuery(g_hDB, OnLookupDone, query, GetClientUserId(client));
}

void OnLookupDone(Handle owner, Handle hndl, const char[] error, any userid)
{
    if (hndl == null)
    {
        LogError("Search failed: %s", error);
        return;
    }

    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    int  now          = GetTime();

    bool isNew        = !SQL_FetchRow(hndl);
    int  prevVisits   = 0;
    int  prevLastSeen = 0;
    int  prevPlayTime = 0;
    if (!isNew)
    {
        prevVisits   = SQL_FetchInt(hndl, 0);    // visits
        prevLastSeen = SQL_FetchInt(hndl, 1);    // last_seen
        prevPlayTime = SQL_FetchInt(hndl, 2);    // play_time (지난 세션까지의 누적, 초)
    }

    // 직전 퇴장 후 짧은 시간 내 재접속(챕터 전환 등)이면 같은 세션으로 보고
    // 인사·방문 카운트를 생략한다. (last_seen은 다음 퇴장 때 다시 갱신됨)
    if (!isNew && now - prevLastSeen <= SESSION_RESUME_SECONDS)
    {
        return;
    }

    int newVisits  = prevVisits + 1;
    int daysAbsent = RoundFloat((now - prevLastSeen) / float(DAY_SECONDS));
    int playHours  = RoundFloat(prevPlayTime / 3600.0);
    if (playHours < 1)
    {
        playHours = 1;
    }

    // 인사 종류 결정 (우선순위 중요)
    int greetType;
    if (isNew)
    {
        greetType = GREET_NEW;
    }
    else if (now - prevLastSeen > LONG_ABSENCE_SECONDS)
    {
        greetType = GREET_LONG;
    }
    else if (newVisits >= REGULAR_VISITS)
    {
        greetType = GREET_REGULAR;
    }
    else
    {
        greetType = GREET_NORMAL;
    }

    char safeId[64];
    SQL_EscapeString(g_hDB, g_sSteamID[client], safeId, sizeof(safeId));

    char query[256];
    if (isNew)
    {
        Format(query, sizeof(query),
               "INSERT INTO visitors (steamid, first_seen, last_seen, visits) " ... "VALUES ('%s', %d, %d, 1)", safeId, now, now);
    }
    else
    {
        Format(query, sizeof(query),
               "UPDATE visitors SET last_seen = %d, visits = visits + 1 " ... "WHERE steamid = '%s'", now, safeId);
    }
    SQL_TQuery(g_hDB, OnUpdateDone, query);

    DataPack pack = new DataPack();
    pack.WriteCell(userid);
    pack.WriteCell(greetType);
    pack.WriteCell(newVisits);
    pack.WriteCell(daysAbsent);
    pack.WriteCell(playHours);
    CreateTimer(GREET_DELAY, Timer_Greet, pack, TIMER_DATA_HNDL_CLOSE);
}

void OnUpdateDone(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        LogError("Writing failed: %s", error);
    }
}

void Timer_Greet(Handle timer, DataPack pack)
{
    pack.Reset();
    int userid     = pack.ReadCell();
    int greetType  = pack.ReadCell();
    int newVisits  = pack.ReadCell();
    int daysAbsent = pack.ReadCell();
    int playHours  = pack.ReadCell();

    int client     = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    if (greetType < 0 || greetType >= sizeof(g_sGreetPhrases))
    {
        LogError("Invalid greetType: %d", greetType);
        return;
    }

    SetGlobalTransTarget(client);
    PrintHintText(client, "%t", g_sGreetPhrases[greetType], client, newVisits, daysAbsent, playHours);
}