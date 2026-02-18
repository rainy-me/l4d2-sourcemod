#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define TEAM_SURVIVOR 2

bool g_bDamageBlocked[MAXPLAYERS + 1] = { false, ... };
bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int errMax)
{
    g_bLateLoad = late;
    return APLRes_Success;
}

public Plugin myinfo =
{
    name        = "L4D2 Get-Up Damage Fix",
    author      = "Rainy",
    description = "일어나는 애니메이션이 진행되는 동안의 무적타임 불일치 문제를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_getup_damage_fix"
};

public void OnPluginStart()
{
    HookEvent("pounce_stopped", OnAnimationsPlaying);
    HookEvent("charger_pummel_end", OnAnimationsPlaying);
    HookEvent("charger_carry_end", OnAnimationsPlaying);
    HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

    if (g_bLateLoad)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                OnClientPutInServer(i);
            }
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKUnhook(client, SDKHook_PostThink, UnblockDamage);
    g_bDamageBlocked[client] = false;
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (IsAliveSurvivor(victim) && g_bDamageBlocked[victim])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bDamageBlocked[i] = false;
        SDKUnhook(i, SDKHook_PostThink, UnblockDamage);
    }
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bDamageBlocked[i] = false;
        SDKUnhook(i, SDKHook_PostThink, UnblockDamage);
    }
}

void OnAnimationsPlaying(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("victim"));
    if (!IsAliveSurvivor(client))
    {
        return;
    }

    CreateTimer(0.2, BlockDamage, GetClientUserId(client));
}

void BlockDamage(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsAliveSurvivor(client))
    {
        return;
    }

    g_bDamageBlocked[client] = true;
    SDKUnhook(client, SDKHook_PostThink, UnblockDamage);
    SDKHook(client, SDKHook_PostThink, UnblockDamage);
}

void UnblockDamage(int client)
{
    if (!IsPlayingGetUpAnim(client))
    {
        g_bDamageBlocked[client] = false;
        SDKUnhook(client, SDKHook_PostThink, UnblockDamage);
    }
}

bool IsAliveSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR);
}

bool IsPlayingGetUpAnim(int client)
{
    int  sequence = GetEntProp(client, Prop_Send, "m_nSequence");
    char model[PLATFORM_MAX_PATH];
    GetClientModel(client, model, sizeof(model));

    if (StrEqual(model, "models/survivors/survivor_gambler.mdl", false))
    {
        return (sequence == 620 || sequence == 667 || sequence == 671 || sequence == 672 || sequence == 629);
    }
    else if (StrEqual(model, "models/survivors/survivor_producer.mdl", false))
    {
        return (sequence == 629 || sequence == 674 || sequence == 678 || sequence == 679 || sequence == 637);
    }
    else if (StrEqual(model, "models/survivors/survivor_coach.mdl", false))
    {
        return (sequence == 621 || sequence == 656 || sequence == 660 || sequence == 661 || sequence == 629);
    }
    else if (StrEqual(model, "models/survivors/survivor_mechanic.mdl", false))
    {
        return (sequence == 625 || sequence == 671 || sequence == 675 || sequence == 676 || sequence == 634);
    }
    else if (StrEqual(model, "models/survivors/survivor_namvet.mdl", false))
    {
        return (sequence == 528 || sequence == 759 || sequence == 763 || sequence == 764 || sequence == 537);
    }
    else if (StrEqual(model, "models/survivors/survivor_teenangst.mdl", false))
    {
        return (sequence == 537 || sequence == 819 || sequence == 823 || sequence == 824 || sequence == 546);
    }
    else if (StrEqual(model, "models/survivors/survivor_manager.mdl", false))
    {
        return (sequence == 528 || sequence == 759 || sequence == 763 || sequence == 764 || sequence == 537);
    }
    else if (StrEqual(model, "models/survivors/survivor_biker.mdl", false))
    {
        return (sequence == 531 || sequence == 762 || sequence == 766 || sequence == 767 || sequence == 540);
    }
    return false;
}
