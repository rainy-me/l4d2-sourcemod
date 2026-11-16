#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define CHECK_INTERVAL 0.2

GlobalForward g_hForwardThirdPersonChanged;
bool          g_bVersus;

// 마지막으로 감지된 3인칭(숄더) 상태
bool          g_bThirdPerson[MAXPLAYERS + 1];

// 사망/팀 변경/구출 등으로 클라이언트 카메라가 1인칭으로 초기화된 상태.
// c_thirdpersonshoulder가 1이어도 실제로는 1인칭이므로, cvar가 0으로 돌아올 때까지 1인칭으로 취급한다.
bool          g_bCameraReset[MAXPLAYERS + 1];

// cvar 쿼리 응답 대기 중 여부와 쿼리를 보낸 시점의 userid.
// 응답 전 중복 쿼리를 막고, 쿼리 도중 슬롯이 재사용된 경우 stale 응답을 무시한다.
bool          g_bQueryPending[MAXPLAYERS + 1];
int           g_iQueryUserId[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "L4D2 Third Person State",
    author      = "Rainy",
    description = "클라이언트의 3인칭(thirdpersonshoulder) 상태를 감지해 다른 플러그인에 알립니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_thirdperson_state"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("TP_IsThirdPerson", Native_IsThirdPerson);
    g_hForwardThirdPersonChanged = new GlobalForward("TP_OnThirdPersonChanged", ET_Ignore, Param_Cell, Param_Cell);
    RegPluginLibrary("l4d2_thirdperson_state");
    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("survivor_rescued", Event_SurvivorRescued);

    // 지연 로드 시 포워드를 기다리지 않고 현재 게임 모드를 반영
    SetVersus(L4D_GetGameModeType() == GAMEMODE_VERSUS);

    CreateTimer(CHECK_INTERVAL, Timer_CheckThirdPerson, _, TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client))
        PushForward(client, false);

    g_bCameraReset[client] = true;
}

public void OnClientDisconnect(int client)
{
    g_bThirdPerson[client]  = false;
    g_bCameraReset[client]  = false;
    g_bQueryPending[client] = false;
    g_iQueryUserId[client]  = 0;
}

public void L4D_OnGameModeChange(int gameMode)
{
    SetVersus(gameMode == GAMEMODE_VERSUS);
}

// 대전 모드에서는 모든 클라이언트를 1인칭으로 통보하고, 대전에서 벗어나면 현재 감지 상태를 다시 통보한다.
void SetVersus(bool versus)
{
    if (versus == g_bVersus)
        return;

    g_bVersus = versus;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
            PushForward(i, g_bThirdPerson[i] && !g_bVersus);
    }
}

Action Timer_CheckThirdPerson(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || IsFakeClient(i) || g_bQueryPending[i])
            continue;

        g_bQueryPending[i] = true;
        g_iQueryUserId[i]  = GetClientUserId(i);
        QueryClientConVar(i, "c_thirdpersonshoulder", ConVarQuery_ThirdPersonShoulder);
    }

    return Plugin_Continue;
}

void ConVarQuery_ThirdPersonShoulder(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    g_bQueryPending[client] = false;

    // 응답이 실패했거나, 쿼리 도중 슬롯이 다른 클라이언트로 재사용된 경우 무시
    if (result != ConVarQuery_Okay || !IsClientInGame(client) || GetClientUserId(client) != g_iQueryUserId[client])
        return;

    bool wasThirdPerson = g_bThirdPerson[client];

    if (!StrEqual(cvarValue, "0"))
    {
        // 3인칭: 카메라 초기화 상태라면 여전히 1인칭으로 취급
        g_bThirdPerson[client] = !g_bCameraReset[client];
    }
    else
    {
        // 1인칭: 사망 중 토글된 경우를 대비해 살아있을 때만 초기화 상태 해제
        if (IsPlayerAlive(client))
            g_bCameraReset[client] = false;

        g_bThirdPerson[client] = false;
    }

    // 상태가 바뀌었을 때만 통보 (포워드는 변화 이벤트)
    if (wasThirdPerson == g_bThirdPerson[client])
        return;

    // 대전 모드에서는 실제 상태와 무관하게 항상 1인칭으로 통보
    PushForward(client, g_bThirdPerson[client] && !g_bVersus);
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

// 클라이언트 카메라가 1인칭으로 초기화되는 이벤트에서 호출.
// 초기화 상태를 기록하고, 다음 폴링까지 기다리지 않고 즉시 1인칭으로 통보한다.
void MarkCameraReset(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    g_bCameraReset[client] = true;

    if (g_bThirdPerson[client])
    {
        g_bThirdPerson[client] = false;
        PushForward(client, false);
    }
}

// 포워드로 통보되는 값과 동일한 현재 상태를 반환 (늦게 로드된 플러그인용)
int Native_IsThirdPerson(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

    return g_bThirdPerson[client] && !g_bVersus;
}

void PushForward(int client, bool thirdPerson)
{
    Call_StartForward(g_hForwardThirdPersonChanged);
    Call_PushCell(client);
    Call_PushCell(thirdPerson);
    Call_Finish();
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
