#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 MOTD",
    author      = "Rainy",
    description = "MOTD를 표시합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_motd"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_info", Cmd_Info);
}

Action Cmd_Info(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "This command can only be used in-game.");
        return Plugin_Handled;
    }

    char lang[6];
    GetLanguageInfo(GetClientLanguage(client), lang, sizeof(lang));

    if (StrEqual(lang, "ko", false))
    {
        ShowMOTDPanel(client, "Rainy 로컬 서버", "motd_rainy_ko.txt", MOTDPANEL_TYPE_FILE);
    }
    else
    {
        ShowMOTDPanel(client, "Rainy Local Server", "motd_rainy_en.txt", MOTDPANEL_TYPE_FILE);
    }
    return Plugin_Handled;
}
