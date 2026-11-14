#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <hxlib>

#define SPIT_MIN_FLAMES 2

bool   g_bLateLoad;

ConVar g_hConVarFizzleOnStagger;
ConVar g_hConVarFizzleOnDeath;

bool   g_bFizzleOnStagger;
bool   g_bFizzleOnDeath;

int    g_iSpittersProjectile[MAXPLAYERS_L4D2 + 1] = { INVALID_ENT_REFERENCE, ... };
int    g_iSpittersPuddle[MAXPLAYERS_L4D2 + 1]     = { INVALID_ENT_REFERENCE, ... };

public Plugin myinfo =
{
    name        = "L4D2 Spit Fizzle",
    author      = "Rainy",
    description = "스피터가 죽거나 비틀거리면 스핏 투사체가 사라지고 스핏 웅덩이가 더 이상 커지지 않습니다.",
    version     = "1.0.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_spit_fizzle"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    g_bLateLoad = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hConVarFizzleOnStagger = CreateConVar(
        "l4d2_spit_fizzle_on_stagger", "1",
        "When a spitter staggers, should their spit projectile be deleted and their spit puddle's growth be stopped?",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hConVarFizzleOnStagger.AddChangeHook(ConVarChanged_Update);

    g_hConVarFizzleOnDeath = CreateConVar(
        "l4d2_spit_fizzle_on_death", "1",
        "When a spitter dies, should their spit projectile be deleted and their spit puddle's growth be stopped?",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hConVarFizzleOnDeath.AddChangeHook(ConVarChanged_Update);
    AutoExecConfig(true, "l4d2_spit_fizzle");

    ReadConVars();

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("spit_burst", Event_SpitBurst);

    if (g_bLateLoad)
        HXLibRescanForwards();
}

public void OnClientPutInServer(int client)
{
    g_iSpittersProjectile[client] = INVALID_ENT_REFERENCE;
    g_iSpittersPuddle[client]     = INVALID_ENT_REFERENCE;
}

public void OnClientDisconnect(int client)
{
    if (!g_bFizzleOnDeath)
        return;
    if (!IsSpitter(client))
        return;
    if (!IsPlayerAlive(client))
        return;

    Fizzle(client);
}

void ConVarChanged_Update(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ReadConVars();
}

void ReadConVars()
{
    g_bFizzleOnStagger = g_hConVarFizzleOnStagger.BoolValue;
    g_bFizzleOnDeath   = g_hConVarFizzleOnDeath.BoolValue;
}

/*********************************************
 * associate puddles/projectiles with spitters
 *********************************************/
public void OnCreateSpitterProjectile_Post(int spitter, int projectile, const float origin[3], const float angles[3], const float velocity[3], const float rotation[3], bool handled)
{
    if (handled || !IsValidClient(spitter))
        return;
    g_iSpittersProjectile[spitter] = EntIndexToEntRef(projectile);
}

void Event_SpitBurst(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    int puddle = event.GetInt("subject", INVALID_ENT_REFERENCE);
    if (!IsValidEdict(puddle))
        return;

    g_iSpittersPuddle[client] = EntIndexToEntRef(puddle);
}

/******************
 * trigger fizzle
 *****************/
public void L4D2_OnStagger_Post(int client, int source)
{
    HandleStagger(client);
}

public void L4D_OnShovedBySurvivor_Post(int client, int victim, const float dir[3])
{
    HandleStagger(victim);
}

void HandleStagger(int client)
{
    if (!g_bFizzleOnStagger)
        return;
    if (!IsSpitter(client))
        return;

    Fizzle(client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bFizzleOnDeath)
        return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsSpitter(client))
        return;

    Fizzle(client);
}

void Fizzle(int client)
{
    int entity = EntRefToEntIndex(g_iSpittersProjectile[client]);
    if (entity != INVALID_ENT_REFERENCE)
        RemoveEntity(entity);

    entity = EntRefToEntIndex(g_iSpittersPuddle[client]);
    if (entity != INVALID_ENT_REFERENCE)
        GetInferno(entity).maxFlames = SPIT_MIN_FLAMES;
}

/*******
 * misc
 *******/

bool IsSpitter(int entity)
{
    return IsValidClient(entity)
        && GetClientTeam(entity) == Team_Infected
        && GetZombieClass(entity) == ZClass_Spitter;
}
