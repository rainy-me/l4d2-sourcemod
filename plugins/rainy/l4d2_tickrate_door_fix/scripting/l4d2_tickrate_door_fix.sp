#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define MAX_EDICTS             2048    //(1 << 11)
#define ENTITY_MAX_NAME_LENGTH 64

enum struct DoorsData
{
    float speed;
}

static const char g_sDoorsTypeTracked[][ENTITY_MAX_NAME_LENGTH] = {
    "prop_door_rotating",
    "prop_door_rotating_checkpoint"
};

DoorsData g_esDoors[MAX_EDICTS];
ConVar    g_hCvarDoorSpeed;
float     g_fDoorSpeed;

public Plugin myinfo =
{
    name        = "L4D2 Tickrate Door Fix",
    author      = "Rainy",
    description = "틱레이트 변경에 따른 문 속도 문제를 고칩니다.",
    version     = "1.0.3",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_tickrate_door_fix"
};

public void OnPluginStart()
{
    g_hCvarDoorSpeed = CreateConVar(
        "door_speed_multiplier", "1.6",
        "Sets the speed of all prop_door entities on a map. 1.05 = 105% speed",
        FCVAR_NONE, true, 0.1);
    g_hCvarDoorSpeed.AddChangeHook(Cvar_Changed);
    AutoExecConfig(true, "l4d2_tickrate_door_fix");

    g_fDoorSpeed = g_hCvarDoorSpeed.FloatValue;

    Door_GetSettingsAll();
    Door_SetSettingsAll();
}

public void OnPluginEnd()
{
    Door_ResetSettingsAll();
}

public void OnEntityCreated(int entity, const char[] className)
{
    if (className[0] != 'p')
        return;

    for (int i = 0; i < sizeof(g_sDoorsTypeTracked); i++)
    {
        if (strcmp(className, g_sDoorsTypeTracked[i], false) != 0)
            continue;
        SDKHook(entity, SDKHook_SpawnPost, Hook_DoorSpawnPost);
        break;
    }
}

void Hook_DoorSpawnPost(int entity)
{
    if (!IsValidEntity(entity))
        return;

    // Save Original Settings.
    Door_GetSettings(entity);

    // Set Settings.
    Door_SetSettings(entity);
}

void Cvar_Changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_fDoorSpeed = g_hCvarDoorSpeed.FloatValue;
    Door_SetSettingsAll();
}

void Door_SetSettingsAll()
{
    int entity = -1;

    for (int i = 0; i < sizeof(g_sDoorsTypeTracked); i++)
    {
        while ((entity = FindEntityByClassname(entity, g_sDoorsTypeTracked[i])) != INVALID_ENT_REFERENCE)
            Door_SetSettings(entity);

        entity = -1;
    }
}

void Door_SetSettings(int entity)
{
    float speed = g_esDoors[entity].speed * g_fDoorSpeed;
    SetEntPropFloat(entity, Prop_Data, "m_flSpeed", speed);
}

void Door_ResetSettingsAll()
{
    int entity = -1;

    for (int i = 0; i < sizeof(g_sDoorsTypeTracked); i++)
    {
        while ((entity = FindEntityByClassname(entity, g_sDoorsTypeTracked[i])) != INVALID_ENT_REFERENCE)
            Door_ResetSettings(entity);

        entity = -1;
    }
}

void Door_ResetSettings(int entity)
{
    float speed = g_esDoors[entity].speed;
    SetEntPropFloat(entity, Prop_Data, "m_flSpeed", speed);
}

void Door_GetSettingsAll()
{
    int entity = -1;

    for (int i = 0; i < sizeof(g_sDoorsTypeTracked); i++)
    {
        while ((entity = FindEntityByClassname(entity, g_sDoorsTypeTracked[i])) != INVALID_ENT_REFERENCE)
            Door_GetSettings(entity);

        entity = -1;
    }
}

void Door_GetSettings(int entity)
{
    g_esDoors[entity].speed = GetEntPropFloat(entity, Prop_Data, "m_flSpeed");
}
