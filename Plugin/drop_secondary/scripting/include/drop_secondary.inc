#if defined _drop_secondary_included
    #endinput
#endif
#define _drop_secondary_included

/**
 * @brief Called when a dead survivor drops their secondary weapon
 *
 * @param client    Client index of the dead survivor
 * @param weapon    Entity index of the dropped secondary weapon
 * @noreturn
 */
forward void L4D2_OnSecondaryWeaponDrop(int client, int weapon);

public SharedPlugin __pl_drop_secondary = {
    name = "drop_secondary",
    file = "drop_secondary.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
