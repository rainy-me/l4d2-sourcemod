#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define CHECK_INTERVAL 0.2

GlobalForward g_hOnThirdPersonChanged;
ConVar        g_hCvarGameMode;

bool          g_bVersus                         = false;
bool          g_bWasVersus                      = false;

// 마지막으로 감지된 3인칭(숄더) 상태
bool          g_bThirdPerson[MAXPLAYERS + 1]    = { false, ... };

// 사망/팀 변경/구출 등으로 클라이언트 카메라가 1인칭으로 초기화된 상태.
// c_thirdpersonshoulder가 1이어도 실제로는 1인칭이므로, cvar가 0으로 돌아올 때까지 1인칭으로 취급한다.
bool          g_bThirdPersonFix[MAXPLAYERS + 1] = { false, ... };

public Plugin myinfo =
{
    name        = "ThirdPersonShoulder_Detect",
    author      = "Rainy",
    description = "Detects thirdpersonshoulder command for other plugins to use",
    version     = "1.6.0",
    url         = "https://forums.alliedmods.net/showthread.php?p=2529779"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_hOnThirdPersonChanged = new GlobalForward("TP_OnThirdPersonChanged", ET_Event, Param_Cell, Param_Cell);
    RegPluginLibrary("ThirdPersonShoulder_Detect");
    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("survivor_rescued", Event_SurvivorRescued);

    g_hCvarGameMode = FindConVar("mp_gamemode");
    g_hCvarGameMode.AddChangeHook(OnConVarChanged);

    CreateTimer(CHECK_INTERVAL, Timer_ThirdPersonCheck, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    UpdateGameMode();
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client))
    {
        PushForward(client, false);
    }
    g_bThirdPersonFix[client] = true;
}

public void OnClientDisconnect(int client)
{
    g_bThirdPerson[client]    = false;
    g_bThirdPersonFix[client] = false;
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateGameMode();
}

// 대전 모드에서는 모든 클라이언트를 1인칭으로 통보하고, 대전에서 벗어나면 현재 감지 상태를 다시 통보한다.
void UpdateGameMode()
{
    char sGameMode[7];
    g_hCvarGameMode.GetString(sGameMode, sizeof(sGameMode));

    g_bVersus = StrEqual(sGameMode, "versus", false);

    if (g_bVersus)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i))
            {
                PushForward(i, false);
            }
        }
        g_bWasVersus = true;
    }
    else
    {
        if (g_bWasVersus)
        {
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsValidClient(i))
                {
                    PushForward(i, g_bThirdPerson[i]);
                }
            }
        }
        g_bWasVersus = false;
    }
}

Action Timer_ThirdPersonCheck(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || IsFakeClient(i))
        {
            continue;
        }
        QueryClientConVar(i, "c_thirdpersonshoulder", QueryClientConVarCallback);
    }
    return Plugin_Continue;
}

void QueryClientConVarCallback(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    bool bLastVal = g_bThirdPerson[client];

    if (!StrEqual(cvarValue, "0"))
    {
        // 3인칭: 카메라 초기화 상태라면 여전히 1인칭으로 취급
        g_bThirdPerson[client] = !g_bThirdPersonFix[client];
    }
    else
    {
        // 1인칭: 사망 중 토글된 경우를 대비해 살아있을 때만 초기화 상태 해제
        if (IsClientInGame(client) && IsPlayerAlive(client))
        {
            g_bThirdPersonFix[client] = false;
        }
        g_bThirdPerson[client] = false;
    }

    if (bLastVal == g_bThirdPerson[client])
    {
        return;
    }

    if (g_bVersus)
    {
        PushForward(client, false);
        return;
    }
    PushForward(client, g_bThirdPerson[client]);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    MarkCameraReset(GetClientOfUserId(event.GetInt("userid")));
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    MarkCameraReset(GetClientOfUserId(event.GetInt("userid")));
}

void Event_SurvivorRescued(Event event, const char[] name, bool dontBroadcast)
{
    MarkCameraReset(GetClientOfUserId(event.GetInt("victim")));
}

// 클라이언트 카메라가 1인칭으로 초기화되는 이벤트에서 호출
void MarkCameraReset(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }
    g_bThirdPersonFix[client] = true;
}

void PushForward(int client, bool bIsThirdPerson)
{
    Call_StartForward(g_hOnThirdPersonChanged);
    Call_PushCell(client);
    Call_PushCell(bIsThirdPerson);
    Call_Finish();
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}
