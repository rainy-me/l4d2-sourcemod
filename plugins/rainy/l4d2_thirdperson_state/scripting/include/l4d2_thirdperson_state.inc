#if defined _l4d2_thirdperson_state_included
    #endinput
#endif
#define _l4d2_thirdperson_state_included

/**
 * 클라이언트의 3인칭(숄더) 상태가 바뀌면 호출된다.
 *
 * @param client         클라이언트 인덱스
 * @param thirdPerson    true = 3인칭(숄더), false = 1인칭
 */
forward void TP_OnThirdPersonChanged(int client, bool thirdPerson);

/**
 * 현재 3인칭(숄더) 상태를 반환한다. (마지막 포워드 호출과 같은 값)
 * 포워드를 놓친 늦게 로드된 플러그인에서 쓴다.
 *
 * @param client    클라이언트 인덱스
 * @return          true = 3인칭(숄더), false = 1인칭
 * @error           잘못된 클라이언트 인덱스
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
