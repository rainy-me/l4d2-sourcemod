#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <actions>
#include <hxlib>

#define CVAR_FLAGS FCVAR_NOTIFY

// enum struct 메서드가 참조하므로 enum struct보다 앞에 둔다
ConVar g_hConVarZombieDiscardRangeDefault;
float  g_fZombieDiscardRangeDefault;

ConVar g_hConVarMaxStuckTime;
float  g_fMaxStuckTime;

enum struct CandidateData
{
    int   entRef;

    bool  stuck;
    float stuckTime;

    void Init(int entityRef)
    {
        this.entRef = entityRef;
        this.stuck  = false;
    }

    bool ShouldDespawn()
    {
        if (g_fMaxStuckTime >= 0.0 && this.stuck && (GetGameTime() - this.stuckTime) >= g_fMaxStuckTime)
            return true;

        return false;
    }
}

enum struct Despawner
{
    ArrayList candidates;
    Handle    updater;

    void Init()
    {
        this.candidates = new ArrayList(sizeof(CandidateData));
        this.updater    = null;
    }

    void AddCandidate(int candidate)
    {
        int           entityRef = EntIndexToEntRef(candidate);
        CandidateData data;
        int           index = this.GetCandidate(entityRef, data);

        data.Init(entityRef);

        if (index >= 0)
            this.candidates.SetArray(index, data);
        else
            this.candidates.PushArray(data);

        if (!this.updater)
            this.updater = CreateTimer(0.5, Timer_DespawnerUpdate);
    }

    int GetCandidate(int entityRef, CandidateData data)
    {
        for (int i = 0; i < this.candidates.Length; i++)
        {
            this.candidates.GetArray(i, data);
            if (entityRef == data.entRef)
                return i;
        }

        return -1;
    }

    void SetStuck(int candidate, bool stuck)
    {
        CandidateData data;
        int           index = this.GetCandidate(EntIndexToEntRef(candidate), data);

        if (index >= 0 && data.stuck != stuck)
        {
            data.stuck = stuck;
            if (stuck)
                data.stuckTime = GetGameTime();

            this.candidates.SetArray(index, data);
        }
    }

    void Update()
    {
        CandidateData candidate;
        int           entity;
        int           i;

        while (i < this.candidates.Length)
        {
            this.candidates.GetArray(i, candidate);
            entity = EntRefToEntIndex(candidate.entRef);

            if (entity == INVALID_ENT_REFERENCE)
            {
                this.candidates.Erase(i);
                continue;
            }

            if (candidate.ShouldDespawn())
            {
                float pos[3];
                GetCollisionCenter(entity, pos);
                float despawnRange = GetScriptValueFloat("ZombieDiscardRange", g_fZombieDiscardRangeDefault);

                if (!IsVisibleToTeam(Team_Survivor, pos, despawnRange, _, 0, false, true))
                {
                    // ForcePlayerSuicide는 클라이언트 전용이라 윗치·일반 좀비는 엔티티 제거
                    if (entity <= MaxClients)
                        ForcePlayerSuicide(entity);
                    else
                        RemoveEntity(entity);
                    this.candidates.Erase(i);
                    continue;
                }
            }

            i++;
        }

        if (this.candidates.Length > 0)
            this.updater = CreateTimer(0.5, Timer_DespawnerUpdate);
    }
}

Despawner g_esDespawner;

StringMap g_hMapTargetBehaviors;

public Plugin myinfo =
{
    name        = "L4D2 Despawn Stuck Infected",
    author      = "Rainy",
    description = "끼인 좀비를 제거합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_despawn_stuck_infected"
};

public void OnPluginStart()
{
    g_hConVarZombieDiscardRangeDefault = FindConVar("z_discard_range");
    g_hConVarZombieDiscardRangeDefault.AddChangeHook(ConVarChanged_Update);

    g_hConVarMaxStuckTime = CreateConVar(
        "l4d2_despawn_stuck_infected_max_stuck_time", "8.0",
        "time in seconds an infected must be stuck to be a candidate " ... "for being despawned. -1.0 to disable stuck despawns",
        CVAR_FLAGS, true, -1.0);
    g_hConVarMaxStuckTime.AddChangeHook(ConVarChanged_Update);
    AutoExecConfig(true, "l4d2_despawn_stuck_infected");

    ReadConVars();

    g_hMapTargetBehaviors = new StringMap();
    g_hMapTargetBehaviors.SetValue("SmokerBehavior", 0);
    g_hMapTargetBehaviors.SetValue("BoomerBehavior", 0);
    g_hMapTargetBehaviors.SetValue("HunterBehavior", 0);
    g_hMapTargetBehaviors.SetValue("SpitterBehavior", 0);
    g_hMapTargetBehaviors.SetValue("JockeyBehavior", 0);
    g_hMapTargetBehaviors.SetValue("ChargerBehavior", 0);
    g_hMapTargetBehaviors.SetValue("TankBehavior", 0);
    g_hMapTargetBehaviors.SetValue("WitchBehavior", 0);
    g_hMapTargetBehaviors.SetValue("InfectedBehavior", 0);

    g_esDespawner.Init();
}

void ConVarChanged_Update(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ReadConVars();
}

void ReadConVars()
{
    g_fZombieDiscardRangeDefault = g_hConVarZombieDiscardRangeDefault.FloatValue;
    g_fMaxStuckTime              = g_hConVarMaxStuckTime.FloatValue;
}

void Timer_DespawnerUpdate(Handle timer)
{
    g_esDespawner.updater = null;
    g_esDespawner.Update();
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name, ActionId id)
{
    if (g_hMapTargetBehaviors.ContainsKey(name))
    {
        g_esDespawner.AddCandidate(actor);
        action.OnStuckPost   = ActionHook_OnStuck;
        action.OnUnStuckPost = ActionHook_OnUnStuck;
    }
}

Action ActionHook_OnStuck(BehaviorAction action, int actor, ActionDesiredResult result)
{
    g_esDespawner.SetStuck(actor, true);
    return Plugin_Continue;
}

Action ActionHook_OnUnStuck(BehaviorAction action, int actor, ActionDesiredResult result)
{
    g_esDespawner.SetStuck(actor, false);
    return Plugin_Continue;
}
