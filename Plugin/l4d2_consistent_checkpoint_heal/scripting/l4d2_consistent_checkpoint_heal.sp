#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

public Plugin myinfo =
{
    name        = "L4D2 Consistent Checkpoint Heal",
    author      = "Rainy",
    description = "맵 전환 시 생존자의 체력을 50까지 회복시키고, 무력화 효과를 제거합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_consistent_checkpoint_heal"
};

public void OnPluginStart()
{
    HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
}

void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2 || !IsPlayerAlive(i))
        {
            continue;
        }

        if (L4D_IsPlayerIncapacitated(i))
        {
            L4D_ReviveSurvivor(i);
        }
        L4D_SetPlayerReviveCount(i, 0);
        L4D_SetPlayerThirdStrikeState(i, false);
        L4D_SetPlayerIsGoingToDie(i, false);

        int currentHealth = GetClientHealth(i);
        if (currentHealth < 50)
        {
            SetEntityHealth(i, 50);
            float currentTempHealth = L4D_GetTempHealth(i);
            float addedHealth       = float(50 - currentHealth);
            float newTempHealth     = currentTempHealth - addedHealth;
            if (newTempHealth < 0.0)
            {
                newTempHealth = 0.0;
            }
            L4D_SetTempHealth(i, newTempHealth);
        }
    }
}
