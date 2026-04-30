#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Player Connect Notifier",
    author      = "Rainy",
    description = "플레이어가 서버에 접속하면 채팅창에 알립니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_player_connect_notifier"
};

public void OnPluginStart()
{
    LoadTranslations("l4d2_player_connect_notifier.phrases");
    HookEvent("player_connect", Event_PlayerConnect);
}

void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    int isBot = event.GetInt("bot");
    if (isBot)
    {
        return;
    }

    char playerName[MAX_NAME_LENGTH];
    event.GetString("name", playerName, sizeof(playerName));

    PrintToChatAll("%t", "Player Joining", playerName);
}
