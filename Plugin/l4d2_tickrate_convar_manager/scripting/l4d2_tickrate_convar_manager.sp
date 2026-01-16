#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Tickrate Convar Manager",
    author      = "Rainy",
    description = "틱레이트와 관련된 convar를 관리합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_tickrate_convar_manager"
};

public void OnPluginStart()
{
    // Get tickrate
    int tickrate = FindConVar("cl_updaterate").IntValue;
    PrintToServer("Set tickrate-related convar values based on %d", tickrate);

    // Remove upper bounds
    FindConVar("sv_minrate").SetBounds(ConVarBound_Upper, false);
    FindConVar("sv_maxrate").SetBounds(ConVarBound_Upper, false);
    FindConVar("net_splitpacket_maxrate").SetBounds(ConVarBound_Upper, false);
    FindConVar("cl_cmdrate").SetBounds(ConVarBound_Upper, false);

    // Set convars
    FindConVar("sv_minrate").IntValue                 = tickrate * 1000;
    FindConVar("sv_maxrate").IntValue                 = tickrate * 1000;
    FindConVar("sv_mincmdrate").IntValue              = tickrate;
    FindConVar("sv_maxcmdrate").IntValue              = tickrate;
    FindConVar("sv_minupdaterate").IntValue           = tickrate;
    FindConVar("sv_maxupdaterate").IntValue           = tickrate;
    FindConVar("net_splitpacket_maxrate").IntValue    = tickrate / 2 * 1000;
    FindConVar("sv_client_min_interp_ratio").IntValue = -1;
}
