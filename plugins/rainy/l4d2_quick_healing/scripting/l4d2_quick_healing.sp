#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <left4dhooks>
#undef REQUIRE_PLUGIN
#include <l4d_heartbeat>
#define REQUIRE_PLUGIN

#define SOUND_HEARTBEAT "player/heartbeatloop.wav"

ConVar    g_hConVarHealPercent;
bool      g_bFastHealUsed[MAXPLAYERS + 1] = { false, ... };
StringMap g_hUsedAuth;

public Plugin myinfo =
{
    name        = "L4D2 Quick Healing",
    author      = "Rainy",
    description = "시작 은신처 내에서 1회 한정 킷을 즉시 사용할 수 있습니다.",
    version     = "1.2.5",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_quick_healing"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_quick_healing.phrases");

    g_hConVarHealPercent = FindConVar("first_aid_heal_percent");

    HookEvent("round_start", Event_RoundStart);
    HookEvent("heal_begin", Event_HealBegin);
    HookEvent("player_bot_replace", Event_PlayerBotReplace);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    g_hUsedAuth = new StringMap();
}

public void OnMapStart()
{
    PrecacheSound("ui/littlereward.wav");
}

public void OnClientPutInServer(int client)
{
    g_bFastHealUsed[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_bFastHealUsed[client] = false;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i < sizeof(g_bFastHealUsed); i++)
        g_bFastHealUsed[i] = false;
    g_hUsedAuth.Clear();
}

// 유휴·퇴장으로 봇이 캐릭터를 넘겨받거나 플레이어가 봇을 넘겨받으면 사용 기록도 따라간다
void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot    = GetClientOfUserId(event.GetInt("bot"));
    if (IsValidClient(player) && IsValidClient(bot) && HasUsed(player))
        g_bFastHealUsed[bot] = true;
}

void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot    = GetClientOfUserId(event.GetInt("bot"));
    if (IsValidClient(player) && IsValidClient(bot) && g_bFastHealUsed[bot])
        g_bFastHealUsed[player] = true;
}

void Event_HealBegin(Event event, const char[] name, bool dontBroadcast)
{
    int healer = GetClientOfUserId(event.GetInt("userid"));
    int healee = GetClientOfUserId(event.GetInt("subject"));
    if (!IsValidClient(healer) || !IsValidClient(healee))
        return;

    if (HasUsed(healee) || !L4D_IsInFirstCheckpoint(healee))
        return;

    // Use quick healing
    g_bFastHealUsed[healee] = true;
    char auth[32];
    if (!IsFakeClient(healee) && GetClientAuthId(healee, AuthId_Steam2, auth, sizeof(auth)))
        g_hUsedAuth.SetValue(auth, true);
    int rawHealth = GetClientHealth(healee);
    int newHealth = RoundToFloor(float(rawHealth) + (100.0 - float(rawHealth)) * g_hConVarHealPercent.FloatValue);
    SetEntityHealth(healee, newHealth);
    L4D_SetTempHealth(healee, 0.0);
    L4D_SetPlayerReviveCount(healee, 0);
    L4D_SetPlayerThirdStrikeState(healee, false);
    L4D_SetPlayerIsGoingToDie(healee, false);

    // heal_success가 나가지 않으므로 흑백 상태의 심장박동 소리와 l4d_heartbeat의 부활 횟수를 직접 정리
    if (GetFeatureStatus(FeatureType_Native, "Heartbeat_SetRevives") == FeatureStatus_Available)
    {
        Heartbeat_SetRevives(healee, 0);
    }
    else
    {
        StopSound(healee, SNDCHAN_AUTO, SOUND_HEARTBEAT);
        StopSound(healee, SNDCHAN_STATIC, SOUND_HEARTBEAT);
    }

    // Notify quick healing use
    if (healer == healee)
    {
        CPrintToChat(healee, "%t", "Quick Heal Self");
        EmitSoundToClient(healee, "ui/littlereward.wav");
    }
    else
    {
        CPrintToChat(healee, "%t", "Quick Heal Received", healer);
        CPrintToChat(healer, "%t", "Quick Heal Given", healee);
        EmitSoundToClient(healee, "ui/littlereward.wav");
        EmitSoundToClient(healer, "ui/littlereward.wav");
    }

    // Stagger healer and cancel immediately
    L4D_StaggerPlayer(healer, healee, NULL_VECTOR);
    CreateTimer(0.1, Timer_CancelStagger, GetClientUserId(healer));

    // Remove the healer's first aid kit.
    int weapon = GetPlayerWeaponSlot(healer, 3);
    if (weapon != -1)
        RemovePlayerItem(healer, weapon);
}

void Timer_CancelStagger(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client))
        L4D_CancelStagger(client);
}

bool HasUsed(int client)
{
    char auth[32];
    return g_bFastHealUsed[client]
        || (!IsFakeClient(client) && GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) && g_hUsedAuth.ContainsKey(auth));
}

bool IsValidClient(int index)
{
    return index > 0 && index <= MaxClients && IsClientInGame(index);
}
