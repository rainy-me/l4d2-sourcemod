#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <multicolors>

public Plugin myinfo =
{
    name        = "L4D2 Random Horde Notifier",
    author      = "Rainy",
    description = "랜덤 웨이브가 발생하면 알림을 표시합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_random_horde_notifier"
};

ConVar g_hCooldownTime;
float  g_fNotifyAllowTime = 0.0;

public void OnPluginStart()
{
    g_hCooldownTime = CreateConVar("l4d2_random_horde_notifier_cooldown_time", "30.0",
                                   "Cooldown time to notify again. (seconds)",
                                   FCVAR_NOTIFY, true, 0.0);
    AutoExecConfig(true, "l4d2_random_horde_notifier");
}

public void L4D_OnSpawnMob_Post(int amount)
{
    if (GetGameTime() > g_fNotifyAllowTime)
    {
        CPrintToChatAll("{green}[{olive}!{green}] Incoming {olive}horde{green}!{default}");
        g_fNotifyAllowTime = GetGameTime() + g_hCooldownTime.FloatValue;
    }
}
