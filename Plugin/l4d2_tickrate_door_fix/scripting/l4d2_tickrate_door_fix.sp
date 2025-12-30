#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define MAX_EDICTS             2048    //(1 << 11)
#define MAX_ENTITY_NAME_LENGTH 64

public Plugin myinfo =
{
    name        = "L4D2 Tickrate Door Fix",
    author      = "Rainy",
    description = "틱레이트 변경에 따른 문 속도 문제를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_tickrate_door_fix"
};

enum
{
    DoorsTypeTracked_None                         = -1,
    DoorsTypeTracked_Prop_Door_Rotating           = 0,
    DoorTypeTracked_Prop_Door_Rotating_Checkpoint = 1
};

static const char g_szDoors_Type_Tracked[][MAX_ENTITY_NAME_LENGTH] = {
    "prop_door_rotating",
    "prop_door_rotating_checkpoint"
};

enum struct DoorsData
{
    int   DoorsData_Type;
    float DoorsData_Speed;
    bool  DoorsData_ForceClose;
}

DoorsData g_ddDoors[MAX_EDICTS];
ConVar    g_hCvarDoorSpeed;
float     g_fDoorSpeed;

public void OnPluginStart()
{
    g_hCvarDoorSpeed = CreateConVar("door_speed_multiplier", "1.55",
                                    "Sets the speed of all prop_door entities on a map. 1.05 = 105% speed",
                                    FCVAR_NONE, true, 0.0);
    g_hCvarDoorSpeed.AddChangeHook(Cvar_Changed);
    AutoExecConfig(true, "l4d2_tickrate_door_fix");

    g_fDoorSpeed = g_hCvarDoorSpeed.FloatValue;

    Door_ClearSettingsAll();
    Door_GetSettingsAll();
    Door_SetSettingsAll();
}

public void OnPluginEnd()
{
    Door_ResetSettingsAll();
}

public void OnEntityCreated(int iEntity, const char[] sClassName)
{
    if (sClassName[0] != 'p')
    {
        return;
    }

    for (int i = 0; i < sizeof(g_szDoors_Type_Tracked); i++)
    {
        if (strcmp(sClassName, g_szDoors_Type_Tracked[i], false) != 0)
        {
            continue;
        }
        SDKHook(iEntity, SDKHook_SpawnPost, Hook_DoorSpawnPost);
    }
}

void Hook_DoorSpawnPost(int iEntity)
{
    if (!IsValidEntity(iEntity))
    {
        return;
    }

    char sClassName[MAX_ENTITY_NAME_LENGTH];
    GetEntityClassname(iEntity, sClassName, sizeof(sClassName));

    // Save Original Settings.
    for (int i = 0; i < sizeof(g_szDoors_Type_Tracked); i++)
    {
        if (strcmp(sClassName, g_szDoors_Type_Tracked[i], false) != 0)
        {
            continue;
        }
        Door_GetSettings(iEntity, i);
    }

    // Set Settings.
    Door_SetSettings(iEntity);
}

void Cvar_Changed(ConVar hConVar, const char[] sOldValue, const char[] sNewValue)
{
    g_fDoorSpeed = g_hCvarDoorSpeed.FloatValue;
    Door_SetSettingsAll();
}

void Door_SetSettingsAll()
{
    int iEntity = -1;

    for (int i = 0; i < sizeof(g_szDoors_Type_Tracked); i++)
    {
        while ((iEntity = FindEntityByClassname(iEntity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
        {
            Door_SetSettings(iEntity);
            SetEntProp(iEntity, Prop_Data, "m_bForceClosed", false);
        }

        iEntity = -1;
    }
}

void Door_SetSettings(int iEntity)
{
    float fSpeed = g_ddDoors[iEntity].DoorsData_Speed * g_fDoorSpeed;
    SetEntPropFloat(iEntity, Prop_Data, "m_flSpeed", fSpeed);
}

void Door_ResetSettingsAll()
{
    int iEntity = -1;

    for (int i = 0; i < sizeof(g_szDoors_Type_Tracked); i++)
    {
        while ((iEntity = FindEntityByClassname(iEntity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
        {
            Door_ResetSettings(iEntity);
        }

        iEntity = -1;
    }
}

void Door_ResetSettings(int iEntity)
{
    float fSpeed = g_ddDoors[iEntity].DoorsData_Speed;
    SetEntPropFloat(iEntity, Prop_Data, "m_flSpeed", fSpeed);
}

void Door_GetSettingsAll()
{
    int iEntity = -1;

    for (int i = 0; i < sizeof(g_szDoors_Type_Tracked); i++)
    {
        while ((iEntity = FindEntityByClassname(iEntity, g_szDoors_Type_Tracked[i])) != INVALID_ENT_REFERENCE)
        {
            Door_GetSettings(iEntity, i);
        }

        iEntity = -1;
    }
}

void Door_GetSettings(int iEntity, int iDoorType)
{
    g_ddDoors[iEntity].DoorsData_Type       = iDoorType;
    g_ddDoors[iEntity].DoorsData_Speed      = GetEntPropFloat(iEntity, Prop_Data, "m_flSpeed");
    g_ddDoors[iEntity].DoorsData_ForceClose = view_as<bool>(GetEntProp(iEntity, Prop_Data, "m_bForceClosed"));
}

void Door_ClearSettingsAll()
{
    for (int i = 0; i < MAX_EDICTS; i++)
    {
        g_ddDoors[i].DoorsData_Type       = DoorsTypeTracked_None;
        g_ddDoors[i].DoorsData_Speed      = 0.0;
        g_ddDoors[i].DoorsData_ForceClose = false;
    }
}