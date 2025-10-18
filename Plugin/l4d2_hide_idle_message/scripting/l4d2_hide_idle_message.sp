#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Hide Idle Message",
    author      = "Rainy",
    description = "유휴 상태 메시지를 채팅창에 표시하지 않습니다.",
    version     = "1.0.0",
    url         = ""
};

public void OnPluginStart()
{
    // 게임 서버가 플레이어들에게 보내는 시스템 메시지를 감지합니다.
    HookUserMessage(GetUserMessageId("TextMsg"), HideIdleMessage, true);
}

public Action HideIdleMessage(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char token[128];
    BfReadString(msg, token, sizeof(token));

    if (StrContains(token, "L4D_idle_spectator") != -1)
    {
        // 유휴 메시지라면 전송을 막습니다.
        return Plugin_Handled;
    }

    // 유휴 메시지가 아니라면 정상적으로 보이게 합니다.
    return Plugin_Continue;
}