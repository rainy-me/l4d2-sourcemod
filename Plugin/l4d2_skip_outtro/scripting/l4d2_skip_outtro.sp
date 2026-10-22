#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <hxlib>

ConVar g_hEnable;

public Plugin myinfo =
{
    name        = "L4D2 Skip Outtro",
    author      = "Rainy",
    description = "맵 클리어 시 아웃트로를 빠르게 건너뜁니다.",
    version     = "1.0.2",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_skip_outtro"
};

public void OnPluginStart()
{
    g_hEnable = CreateConVar(
        "l4d2_skip_outtro_enable", "1",
        "Enable skipping the finale outtro (0 = off, 1 = on)",
        FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "l4d2_skip_outtro");

    HookEvent("finale_vehicle_leaving", Event_FinaleVehicleLeaving, EventHookMode_PostNoCopy);
    HookEvent("finale_win", Event_FinaleWin, EventHookMode_PostNoCopy);
}

void Event_FinaleVehicleLeaving(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hEnable.BoolValue)
    {
        SetTimescale(10.0);
    }
}

void Event_FinaleWin(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hEnable.BoolValue)
    {
        CreateTimer(0.1, Timer_OuttroStatsDone, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

Action Timer_OuttroStatsDone(Handle timer)
{
    // 서버는 플레이어별로 통계 확인 완료를 받으므로 사람 클라이언트마다 보냄
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            FakeClientCommand(i, "outtro_stats_done");
        }
    }
    return Plugin_Continue;
}
