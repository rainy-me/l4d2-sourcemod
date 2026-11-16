#if defined _l4d2_thirdperson_state_included
    #endinput
#endif
#define _l4d2_thirdperson_state_included

/**
 * Called when a client's third-person (shoulder) state changes.
 *
 * @param client         Client index.
 * @param thirdPerson    true = third person (shoulder), false = first person.
 */
forward void TP_OnThirdPersonChanged(int client, bool thirdPerson);

/**
 * Returns the current third-person (shoulder) state (same value as the last forward call).
 * Useful for late-loaded plugins that missed earlier forward calls.
 *
 * @param client    Client index.
 * @return          true = third person (shoulder), false = first person.
 * @error           Invalid client index.
 */
native bool TP_IsThirdPerson(int client);

public SharedPlugin __pl_l4d2_thirdperson_state =
{
    name = "l4d2_thirdperson_state",
    file = "l4d2_thirdperson_state.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_l4d2_thirdperson_state_SetNTVOptional()
{
    MarkNativeAsOptional("TP_IsThirdPerson");
}
#endif
