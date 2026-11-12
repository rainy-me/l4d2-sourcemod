#if defined _ThirdPersonShoulder_Detect_included
	#endinput
#endif
#define _ThirdPersonShoulder_Detect_included

/**
*	Called when a client's thirdperson shoulder state changes.
*
*	@param 	iClient			Client Index.
*	@param 	bIsThirdPerson	true = Is in thirdperson shoulder, false otherwise.
*/
forward void TP_OnThirdPersonChanged(int iClient, bool bIsThirdPerson);

/**
*	Returns the current thirdperson shoulder state (same value as the last forward call).
*	Useful for late-loaded plugins that missed earlier forward calls.
*
*	@param 	iClient			Client Index.
*	@return					true = Is in thirdperson shoulder, false otherwise.
*	@error					Invalid client index.
*/
native bool TP_IsThirdPerson(int iClient);

public SharedPlugin __pl_ThirdPersonShoulder_Detect =
{
	name = "ThirdPersonShoulder_Detect",
	file = "ThirdPersonShoulder_Detect.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_ThirdPersonShoulder_Detect_SetNTVOptional()
{
	MarkNativeAsOptional("TP_IsThirdPerson");
}
#endif
