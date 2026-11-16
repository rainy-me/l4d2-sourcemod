#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define CHECK_INTERVAL 0.2

GlobalForward g_hForwardThirdPersonChanged;
bool          g_bVersus;

// Last detected third-person (shoulder) state
bool          g_bThirdPerson[MAXPLAYERS + 1];

// The client camera was reset to first person by death, team change, rescue, etc.
// c_thirdpersonshoulder can still be 1 while the view is first person, so treat it as first person until the cvar returns to 0.
bool          g_bCameraReset[MAXPLAYERS + 1];

// Whether a cvar query is awaiting its reply, and the userid at the time it was sent.
// Prevents duplicate queries and ignores stale replies when the slot was reused mid-query.
bool          g_bQueryPending[MAXPLAYERS + 1];
int           g_iQueryUserId[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "L4D2 Third Person State",
    author      = "Rainy",
    description = "클라이언트의 3인칭(thirdpersonshoulder) 상태를 감지해 다른 플러그인에 알립니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/libs/l4d2_thirdperson_state"
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

    // On late load, apply the current game mode without waiting for the forward
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

// In versus every client is reported as first person; on leaving versus the detected state is reported again.
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

    // Ignore failed replies and replies for a slot that was reused by another client mid-query
    if (result != ConVarQuery_Okay || !IsClientInGame(client) || GetClientUserId(client) != g_iQueryUserId[client])
        return;

    bool wasThirdPerson = g_bThirdPerson[client];

    if (!StrEqual(cvarValue, "0"))
    {
        // Third person: still first person while the camera is in the reset state
        g_bThirdPerson[client] = !g_bCameraReset[client];
    }
    else
    {
        // First person: clear the reset state only while alive, in case it was toggled while dead
        if (IsPlayerAlive(client))
            g_bCameraReset[client] = false;

        g_bThirdPerson[client] = false;
    }

    // Notify only when the state changed (the forward is a change event)
    if (wasThirdPerson == g_bThirdPerson[client])
        return;

    // In versus always report first person regardless of the actual state
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

// Called on events that reset the client camera to first person.
// Records the reset state and reports first person right away instead of waiting for the next poll.
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

// Returns the current state, the same value the forward reports (for late-loaded plugins)
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
