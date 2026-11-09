#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d_pellet_spread_customizer>

// You can use the visualise_impacts.smx plugin to test the resulting spread.
// It will render small purple boxes where the server-side pellets land.

ConVar g_hCvarCenterPellet = null;

public Plugin myinfo =
{
	name = "L4D2 Static Shotgun Spread",
	author = "Jahze, Visor, A1m`, Rena, Forgetest",
	version = "2.0",
	description = "Apply circular pattern to shotgun spreads",
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

public void OnPluginStart()
{
	g_hCvarCenterPellet = CreateConVar("sgspread_center_pellet", "1", "Center pellet: 0 - off, 1 - on.", _, true, 0.0, true, 1.0);
}

public Action L4D_OnPelletFirstBullet(int weapon)
{
	return g_hCvarCenterPellet.BoolValue ? Plugin_Continue : Plugin_Handled;
}

// 0 ~ nMaxPellets-1. Works whether nPellet is 0-based or 1-based, both forwards get the same slot.
int PelletSlot(int nPellet, int nMaxPellets)
{
	return nPellet % nMaxPellets;
}

// Slot direction on a full circle. Vanilla angle is [0, 180] and a negative spread covers the other half.
float SlotDirection(int slot, int nMaxPellets)
{
	return 360.0 * slot / nMaxPellets;
}

public Action L4D_OnPelletSpread(int weapon, float &spread, int nPellet, int nMaxPellets)
{
	if (nMaxPellets <= 0)
		return Plugin_Continue;

	int slot = PelletSlot(nPellet, nMaxPellets);

	// Vanilla |spread| is uniform in [0, max]; place one pellet at the middle of each equal slice.
	spread *= (slot + 0.5) / nMaxPellets;

	if (SlotDirection(slot, nMaxPellets) >= 180.0)
		spread = -spread;

	return Plugin_Changed;
}

public Action L4D_OnPelletSpreadDir(int weapon, float &angle, int nPellet, int nMaxPellets)
{
	if (nMaxPellets <= 0)
		return Plugin_Continue;

	float dir = SlotDirection(PelletSlot(nPellet, nMaxPellets), nMaxPellets);
	angle = dir >= 180.0 ? dir - 180.0 : dir;
	return Plugin_Changed;
}
