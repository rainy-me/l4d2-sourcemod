#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "L4D2 Suicide",
    author      = "Rainy",
    description = "어드민 권한 없이 !kill 또는 /kill 명령을 사용할 수 있도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_suicide"
};

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Continue;
    }

    char text[16];
    strcopy(text, sizeof(text), sArgs);
    TrimString(text);

    if (!StrEqual(text, "!kill", false) && !StrEqual(text, "/kill", false))
    {
        return Plugin_Continue;
    }

    if (IsPlayerAlive(client))
    {
        ForcePlayerSuicide(client);
    }
    return Plugin_Handled;
}
