#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define GAMEDATA  "l4d2_si_ability"
#define ZC_JOCKEY 5

ConVar      g_hBlockTime;
DynamicHook g_hLeapOnTouch;
int         g_iShovedUserId[MAXPLAYERS + 1];
float       g_fBlockEndTime[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "L4D2 Jockey Shove Cap Block",
    author      = "Rainy",
    description = "생존자에게 밀쳐진 자키가 일정 시간 동안 생존자를 잡지 못하도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_jockey_shove_cap_block"
};

public void OnPluginStart()
{
    GameData hGameData = new GameData(GAMEDATA);
    if (hGameData == null)
    {
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);
    }

    int iOffset = hGameData.GetOffset("CBaseAbility::OnTouch");
    delete hGameData;
    if (iOffset == -1)
    {
        SetFailState("Failed to get offset 'CBaseAbility::OnTouch'.");
    }

    g_hLeapOnTouch = new DynamicHook(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);
    g_hLeapOnTouch.AddParam(HookParamType_CBaseEntity);

    g_hBlockTime = CreateConVar(
        "l4d2_jockey_shove_cap_block_time", "2.0",
        "How long a shoved jockey is blocked from capping survivors (seconds)",
        _, true, 1.0, true, 10.0);

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_shoved", Event_PlayerShoved);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (strcmp(classname, "ability_leap") == 0)
    {
        g_hLeapOnTouch.HookEntity(Hook_Pre, entity, Leap_OnTouch);
    }
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i <= MAXPLAYERS; i++)
    {
        g_iShovedUserId[i] = 0;
        g_fBlockEndTime[i] = 0.0;
    }
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsSurvivor(GetClientOfUserId(event.GetInt("attacker"))))
    {
        return;
    }

    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (IsJockey(client))
    {
        g_iShovedUserId[client] = userid;
        g_fBlockEndTime[client] = GetGameTime() + g_hBlockTime.FloatValue;
    }
}

MRESReturn Leap_OnTouch(int ability, DHookParam hParams)
{
    int jockey = GetEntPropEnt(ability, Prop_Send, "m_owner");
    if (!IsJockey(jockey) || !IsSurvivor(hParams.Get(1)))
    {
        return MRES_Ignored;
    }

    // 같은 슬롯에 다른 플레이어가 들어온 경우를 userid로 걸러낸다.
    if (g_iShovedUserId[jockey] == GetClientUserId(jockey) && g_fBlockEndTime[jockey] >= GetGameTime())
    {
        return MRES_Supercede;
    }

    return MRES_Ignored;
}

bool IsJockey(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_JOCKEY;
}

bool IsSurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2;
}
