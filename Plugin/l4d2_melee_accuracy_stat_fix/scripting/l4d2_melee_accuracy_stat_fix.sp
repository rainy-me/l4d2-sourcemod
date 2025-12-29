#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Melee Accuracy Stat Fix",
    author      = "ChatGPT",
    description = "Exclude melee attacks from accuracy stats",
    version     = "1.0.0",
    url         = ""
};

public void OnPluginStart()
{
    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Pre);
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    // 근접무기면 통계 이벤트 자체를 막음
    if (StrEqual(weapon, "melee"))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}
