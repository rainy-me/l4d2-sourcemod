#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define GESTURE_SLOT    6
#define TONGUE_ACTIVITY "ACT_TERROR_SMOKER_SENDING_OUT_TONGUE"

public Plugin myinfo =
{
    name        = "L4D2 Smoker Antic Fix",
    author      = "Rainy",
    description = "스모커가 혀를 발사할 때 예비 동작 애니메이션이 재생되지 않는 버그를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_smoker_antic_fix"
};

public void OnPluginStart()
{
    HookEvent("ability_use", Event_AbilityUse);
}

void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("context") != 1)
    {
        return;
    }

    char ability[32];
    event.GetString("ability", ability, sizeof(ability));
    if (strcmp(ability, "ability_tongue") != 0)
    {
        return;
    }

    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client))
    {
        return;
    }

    // 시퀀스 번호는 모델마다 다르므로 스모커 기본 모델 기준으로 한 번만 조회해 캐시한다.
    static int sequence = -1;
    static int activity = -1;
    if (sequence == -1)
    {
        char code[160], buffer[8];
        FormatEx(code, sizeof(code), "ret <- GetPlayerFromUserID(%d).LookupSequence(\"%s\"); <RETURN>ret</RETURN>", userid, TONGUE_ACTIVITY);
        if (!L4D2_GetVScriptOutput(code, buffer, sizeof(buffer)))
        {
            return;
        }

        sequence = StringToInt(buffer);
        activity = AnimGetFromActivity(TONGUE_ACTIVITY);
        if (sequence < 0 || activity < 0)
        {
            LogError("시퀀스 조회 실패 (sequence=%d, activity=%d)", sequence, activity);
            sequence = -1;
            return;
        }
    }

    // 같은 모델을 다시 세팅해 애니메이션 상태를 리셋한다.
    char model[PLATFORM_MAX_PATH];
    GetClientModel(client, model, sizeof(model));
    SetEntityModel(client, model);

    SetEntProp(client, Prop_Send, "m_NetGestureSequence", sequence, _, GESTURE_SLOT);
    SetEntProp(client, Prop_Send, "m_NetGestureActivity", activity, _, GESTURE_SLOT);
    SetEntPropFloat(client, Prop_Send, "m_NetGestureStartTime", GetGameTime(), GESTURE_SLOT);
}
