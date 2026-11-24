#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define RESPAWN_DELAY 3.0
#define KILL_DELAY    0.5

ConVar g_hConVarEnable;

public Plugin myinfo =
{
    name        = "L4D2 No Survivor Bots",
    author      = "Rainy",
    description = "생존자 봇을 처치하고 중도 참가자를 부활시킵니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_no_survivor_bots"
};

public void OnPluginStart()
{
    g_hConVarEnable = CreateConVar(
        "l4d2_no_survivor_bots_enable", "1",
        "1=ON, 0=OFF",
        FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_no_survivor_bots");

    RegAdminCmd("sm_killbots", Cmd_Killbots, ADMFLAG_ROOT, "Kill bot survivors");
    RegAdminCmd("sm_kb", Cmd_Killbots, ADMFLAG_ROOT, "Kill bot survivors");
}

public void OnClientPutInServer(int client)
{
    if (!IsEnabled() || !IsClientInGame(client) || IsFakeClient(client))
        return;

    CreateTimer(RESPAWN_DELAY, Timer_RespawnNewPlayer, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    if (!IsEnabled() || IsFakeClient(client))
        return;

    CreateTimer(KILL_DELAY, Timer_KillBots, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    if (IsEnabled())
        KillBots();
}

// 대전(versus, teamversus, 대전 계열 변이)과 스캐빈지에서는 작동하지 않는다
bool IsEnabled()
{
    return g_hConVarEnable.BoolValue && !(L4D_GetGameModeType() & (GAMEMODE_VERSUS | GAMEMODE_SCAVENGE));
}

Action Cmd_Killbots(int client, int args)
{
    KillBots();
    return Plugin_Handled;
}

Action Timer_RespawnNewPlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
        return Plugin_Stop;
    // 로딩이 느리면 아직 생존자 팀에 들어오지 않았을 수 있으므로 들어올 때까지 다시 확인
    if (GetClientTeam(client) != 2)
        return Plugin_Continue;

    RespawnNewPlayer(client);
    return Plugin_Stop;
}

void Timer_KillBots(Handle timer)
{
    if (L4D_HasAnySurvivorLeftSafeArea())
        KillBots();
}

// Methods
// ------------------------------------
void KillBots()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != 2)
            continue;
        if (IsIdlePlayer(i))
            continue;

        ForcePlayerSuicide(i);
    }
}

void RespawnNewPlayer(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || IsPlayerAlive(client) || GetClientTeam(client) != 2)
        return;

    L4D2_VScriptWrapper_ReviveByDefib(client);
    SetEntityHealth(client, GetEntProp(client, Prop_Data, "m_iMaxHealth"));
    GivePlayerItem(client, "weapon_smg_silenced");
    GivePlayerItem(client, "weapon_first_aid_kit");

    int target = GetLowestFlowSurvivor(client);
    if (target != -1)
    {
        float pos[3], ang[3];
        GetClientAbsOrigin(target, pos);
        GetClientAbsAngles(target, ang);
        TeleportEntity(client, pos, ang);
        L4D_WarpToValidPositionIfStuck(client);
    }
}

// Helpers
// ------------------------------------
int GetLowestFlowSurvivor(int exclude)
{
    int   best = -1;
    float bestFlow;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == exclude || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != 2)
            continue;

        float flow = L4D2Direct_GetFlowDistance(i);
        if (best == -1 || flow < bestFlow)
        {
            best     = i;
            bestFlow = flow;
        }
    }
    return best;
}

bool IsIdlePlayer(int client)
{
    return GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") > 0;
}

bool IsValidClient(int index)
{
    return index > 0 && index <= MaxClients && IsClientInGame(index);
}
