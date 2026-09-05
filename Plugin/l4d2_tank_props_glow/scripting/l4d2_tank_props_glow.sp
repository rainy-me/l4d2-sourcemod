#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define TANK_CHECK_INTERVAL 1.0
#define TEAM_INFECTED       3
#define Z_TANK              8

ConVar g_hGlowColor;
ConVar g_hGlowRange;
ConVar g_hFlashing;

public Plugin myinfo =
{
    name        = "L4D2 Tank Props Glow",
    author      = "Rainy",
    description = "탱크가 날릴 수 있는 물체에 글로우 효과를 줍니다.",
    version     = "1.2.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_tank_props_glow"
};

public void OnPluginStart()
{
    g_hGlowColor = CreateConVar(
        "l4d2_tank_props_glow_color", "255 0 0",
        "Glow color (RGB) for props.",
        FCVAR_NOTIFY);
    g_hGlowRange = CreateConVar(
        "l4d2_tank_props_glow_range", "700",
        "Glow range for props. (0=unlimited)",
        FCVAR_NOTIFY, true, 0.0);
    g_hFlashing = CreateConVar(
        "l4d2_tank_props_glow_flashing", "0",
        "Flashing glow effect for props. (0=OFF, 1=ON)",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_tank_props_glow");

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("tank_killed", Event_TankKilled);
    HookEvent("round_end", Event_RoundEnd);
}

public void OnPluginEnd()
{
    ToggleTankPropsGlow(false);
}

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    ToggleTankPropsGlow(true);
    // tank_killed 없이 탱크가 사라지는 경우 대비
    CreateTimer(TANK_CHECK_INTERVAL, Timer_CheckTanks, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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

Action Timer_CheckTanks(Handle timer)
{
    if (IsAnyTankAlive())
    {
        return Plugin_Continue;
    }
    ToggleTankPropsGlow(false);
    return Plugin_Stop;
}

void ToggleTankPropsGlow(bool enable)
{
    int color[3];
    if (enable)
    {
        GetColor(color);
    }

    static const char classnames[][] = { "prop_physics", "prop_car_alarm" };
    for (int i = 0; i < sizeof(classnames); i++)
    {
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, classnames[i])) != -1)
        {
            if (!L4D_IsTankProp(entity))
            {
                continue;
            }

            if (enable)
            {
                L4D2_SetEntityGlow(entity, L4D2Glow_Constant, g_hGlowRange.IntValue,
                                   0, color, g_hFlashing.BoolValue);
            }
            else
            {
                L4D2_RemoveEntityGlow(entity);
            }
        }
    }
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
    return (IsClient(client) && IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED && IsPlayerAlive(client) && IsTank(client));
}

bool IsTank(int client)
{
    return (GetEntProp(client, Prop_Send, "m_zombieClass") == Z_TANK);
}

bool IsClient(int index)
{
    return index > 0 && index <= MaxClients;
}

void GetColor(int color[3])
{
    char sColor[32];
    g_hGlowColor.GetString(sColor, sizeof(sColor));
    if (!StringToColor(sColor, color))
    {
        SetFailState("Invalid color format.");
    }
}

bool StringToColor(const char[] str, int color[3])
{
    char sColor[3][8];
    if (ExplodeString(str, " ", sColor, sizeof(sColor), sizeof(sColor[])) != 3)
    {
        return false;
    }

    for (int i = 0; i < sizeof(sColor); i++)
    {
        if (!StringToIntEx(sColor[i], color[i]) || color[i] < 0 || color[i] > 255)
            return false;
    }
    return true;
}
