#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define Z_TANK        8
#define TEAM_INFECTED 3

public Plugin myinfo =
{
    name        = "L4D2 Tank Props Glow",
    author      = "Rainy",
    description = "탱크가 날릴 수 있는 물체에 글로우 효과를 줍니다.",
    version     = "1.0.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_tank_props_glow"
};

ConVar g_hCvarGlowColor;
ConVar g_hCvarGlowRange;
ConVar g_hCvarFlashing;

public void OnPluginStart()
{
    g_hCvarGlowColor = CreateConVar("l4d2_tank_props_glow_color", "255 0 0",
                                    "Glow color (RGB) for props.",
                                    FCVAR_NONE);
    g_hCvarGlowRange = CreateConVar("l4d2_tank_props_glow_range", "1800",
                                    "Glow range for props. (0 = unlimited)",
                                    FCVAR_NONE, true, 0.0);
    g_hCvarFlashing  = CreateConVar("l4d2_tank_props_glow_flashing", "0",
                                    "Flashing glow effect for props. (0 = disabled, 1 = enabled)",
                                    FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_tank_props_glow");

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("tank_killed", Event_TankKilled);
    HookEvent("round_end", Event_RoundEnd);
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    ToggleTankPropsGlow(true);
}

void Event_TankKilled(Event event, const char[] name, bool dontBroadcast)
{
    RequestFrame(CheckTanksAndRemoveGlow);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    ToggleTankPropsGlow(false);
}

void CheckTanksAndRemoveGlow()
{
    if (!IsAnyTankAlive())
    {
        ToggleTankPropsGlow(false);
    }
}

void ToggleTankPropsGlow(bool enable)
{
    int color[3];
    GetColor(color);

    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "prop_physics")) != -1)
    {
        if (IsValidEntity(entity) && IsTankProp(entity))
        {
            if (enable)
            {
                L4D2_SetEntityGlow(entity, L4D2Glow_Constant, g_hCvarGlowRange.IntValue,
                                   0, color, g_hCvarFlashing.BoolValue);
            }
            else
            {
                L4D2_RemoveEntityGlow(entity);
            }
        }
    }

    entity = -1;
    while ((entity = FindEntityByClassname(entity, "prop_car_alarm")) != -1)
    {
        if (IsValidEntity(entity))
        {
            if (enable)
            {
                L4D2_SetEntityGlow(entity, L4D2Glow_Constant, g_hCvarGlowRange.IntValue,
                                   0, color, g_hCvarFlashing.BoolValue);
            }
            else
            {
                L4D2_RemoveEntityGlow(entity);
            }
        }
    }
}

bool IsTankProp(int entity)
{
    char modelName[128];
    GetEntPropString(entity, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    if (StrContains(modelName, "forklift", false) != -1) return true;        // 지게차
    if (StrContains(modelName, "dumpster", false) != -1) return true;        // 쓰레기통
    if (StrContains(modelName, "atlas_ball", false) != -1) return true;      // 아틀라스 볼
    if (StrContains(modelName, "brick_pallet", false) != -1) return true;    // 벽돌 팔레트
    if (StrContains(modelName, "log", false) != -1) return true;             // 통나무
    if (StrContains(modelName, "tree", false) != -1) return true;            // 나무
    if (StrContains(modelName, "vehicle", false) != -1)                      // 자동차류
    {
        if (StrContains(modelName, "car", false) != -1) return true;
    }

    return false;
}

void GetColor(int color[3])
{
    char sColor[12];
    g_hCvarGlowColor.GetString(sColor, sizeof(sColor));
    if (!StringToColor(sColor, color))
    {
        SetFailState("Invalid color format.");
        return;
    }
}

bool StringToColor(const char[] str, int color[3])
{
    char sColor[3][4];
    if (ExplodeString(str, " ", sColor, sizeof(sColor), sizeof(sColor[])) != 3)
    {
        return false;
    }

    for (int i = 0; i < sizeof(sColor); i++)
    {
        if (!StringToIntEx(sColor[i], color[i]))
            return false;
    }
    return true;
}

bool IsAnyTankAlive()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsAliveTank(i))
        {
            return true;
        }
    }
    return false;
}

bool IsAliveTank(int client)
{
    return (IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED && IsPlayerAlive(client) && IsTank(client));
}

bool IsTank(int client)
{
    return (GetEntProp(client, Prop_Send, "m_zombieClass") == Z_TANK);
}