#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define IDLE_MESSAGE_TOKEN "L4D_idle_spectator"

public Plugin myinfo =
{
    name        = "L4D2 Hide Idle Message",
    author      = "Rainy",
    description = "유휴 상태 메시지를 채팅창에 표시하지 않도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_hide_idle_message"
};

public void OnPluginStart()
{
    // 게임 서버가 플레이어들에게 보내는 시스템 메시지를 감지합니다.
    UserMsg msgId = GetUserMessageId("TextMsg");
    if (msgId == INVALID_MESSAGE_ID)
    {
        SetFailState("TextMsg user message not found");
    }
    HookUserMessage(msgId, HideIdleMessage, true);
}

Action HideIdleMessage(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char token[128];
    if (BfReadString(msg, token, sizeof(token)) < 0)
    {
        return Plugin_Continue;    // 읽기 실패 시 처리
    }

    if (StrContains(token, IDLE_MESSAGE_TOKEN, false) != -1)
    {
        // 유휴 메시지라면 전송을 막습니다.
        return Plugin_Handled;
    }

    // 유휴 메시지가 아니라면 정상적으로 보이게 합니다.
    return Plugin_Continue;
}