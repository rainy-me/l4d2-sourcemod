#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Accuracy Stat Fix",
    author      = "갹, Rainy",
    description = "근접무기와 전기톱을 명중률 통계에서 제외합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_accuracy_stat_fix"
};

public void OnPluginStart()
{
    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Pre);
}

Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (StrEqual(weapon, "melee") || StrEqual(weapon, "chainsaw"))
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}