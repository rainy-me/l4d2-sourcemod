# 자작 플러그인 코드 스타일

자작 플러그인(`plugins/rainy`, `plugins/archive`)의 `<plugin>/scripting/<plugin>.sp`에 적용한다.

## 파일 순서

1. `#pragma semicolon 1` / `#pragma newdecls required`
2. `#include` (sourcemod → sdktools/sdkhooks 등 기본 → 외부 라이브러리)
3. `#define`, 그 뒤에 enum / enum struct / methodmap 같은 타입 정의
4. 전역 변수
5. `public Plugin myinfo`
6. `public void OnPluginStart()` (`AskPluginLoad2`가 있으면 그 바로 앞)
7. 함수들
8. 헬퍼 함수들 — 파일 맨 끝

- enum struct 메서드가 전역을 참조하면 그 전역만 enum struct 앞에 둔다(뒤에 두면 컴파일 에러). 그 전역이 ConVar 캐시 값이면 짝이 되는 `g_hConVar*` 핸들도 함께 앞에 둔다.

### 함수 영역(7) 안의 순서

1. 플러그인 수명 forward: OnPluginEnd → OnAllPluginsLoaded → OnLibraryAdded/OnLibraryRemoved → OnConfigsExecuted → OnMapStart → OnMapEnd
2. 클라이언트 forward: OnClientPutInServer → OnClientDisconnect → 그 밖의 OnClient* → OnPlayerRunCmd/OnPlayerRunCmdPost
3. 엔티티·프레임 forward: OnEntityCreated → OnEntityDestroyed → OnGameFrame
4. 나머지(이벤트, 콜백, 명령, 타이머, 외부 라이브러리 forward, 플러그인 전용 함수): 기능 흐름대로 묶는다.

### 헬퍼 기준

- 헬퍼 = 값만 계산해 반환값이나 출력 매개변수로 돌려주는 함수. forward·콜백이 아니고, 플러그인 전역을 읽거나 쓰지 않고, 게임 상태를 바꾸지 않는다(조회만 함). `IsClient`, `IsValidSurvivor`, `GetClosestSurvivor`, `GetRandomSpin` 등. 파일 맨 끝에 둔다.
- 전역을 읽거나 쓰는 함수, 엔티티·ConVar·파일·사운드 등에 부수효과가 있는 함수(`ReadConVars`, `ResetClient`, `KillBots`, `PrecacheSounds` 등)는 헬퍼가 아니며 함수 영역에서 호출 흐름에 맞는 자리에 둔다.

## public

- `public`은 꼭 필요한 곳에만 단다: `myinfo`, 그리고 이름으로 호출되는 forward(OnPluginStart, OnMapStart, OnClientPutInServer, AskPluginLoad2, left4dhooks의 L4D_On*/L4D2_On* 등 include에 `forward`로 선언된 것).
- 이벤트·타이머·SDKHook·명령·ConVar 변경·DHook·RequestFrame 콜백처럼 함수 참조로 넘기는 함수에는 달지 않는다.
- forward에서 `public`을 빼면 컴파일 에러 없이 호출만 안 되므로, 뺄 때는 include의 `forward` 선언 여부를 확인한다.

## 중괄호

- Allman 스타일, 들여쓰기 스페이스 4칸.
- enum은 `};`로, enum struct는 `}`로 닫는다. enum 마지막 값 뒤에는 쉼표를 쓰지 않는다.
- if / else / for / while 본문이 한 줄 문장 하나면 중괄호를 쓰지 않고 다음 줄에 들여쓴다. `if (x) return;`처럼 같은 줄에 쓰지 않는다.
  ```
  if (!IsClientInGame(client))
      return;
  ```
- 가독성을 위해 중괄호를 유지하는 경우:
  - if / else if / else 체인 중 한 분기라도 여러 문장이면 체인 전체
  - 본문이 여러 줄에 걸치는 경우(조건이나 호출이 줄바꿈됨, for 본문이 중괄호 없는 if)
  - 본문에 주석 줄이 함께 있는 경우

## 정렬

- 기준은 VS Code SourcePawn Studio 확장의 포매터(기본 설정) 출력이다.
- 연속된 변수 선언은 타입 뒤 이름을, 연속된 대입은 `=`를, 연속된 `#define`은 값을 세로로 맞춘다. 사이에 빈 줄이나 주석 줄만 있으면 같은 그룹으로 보고 함께 맞춘다.
  ```
  ConVar g_hConVarRadius;
  float  g_fRadius;

  this.bufferLen = 0;
  this.overflow  = false;
  ```
- 복합 대입(`+=`, `&=` 등)은 맞추지 않는다.
- 메서드가 있는 enum struct를 가진 파일은 포매터가 메서드를 망가뜨리므로 포매터를 돌리지 않고, 필드와 본문을 같은 규칙으로 손으로 맞춘다.

## 이름

- 지역변수·매개변수: 헝가리안 접두어 없이 lowerCamelCase (`client`, `weapon`, `gameMode`, `victimPos`). 약어 접두어도 쓰지 않는다. 멤버·전역·함수명과 겹치면 다른 의미 있는 이름을 쓴다.
- 전역변수: `g_{type}{PascalCase}`, 접두어 뒤 밑줄 금지.
  - `i` int / `f` float / `b` bool / `s` char[] / `h` Handle 계열(ConVar, ArrayList, StringMap, DynamicHook, GameData 등) / `e` enum / `es` enum struct
  - 배열은 원소 타입 기준 (`float g_fPos[3]`)
  - ConVar는 `g_hConVar{이름}` (`g_hConVarRadius`)
- ConVar 이름 문자열: `l4d2_<plugin>_<설정>` (`l4d2_no_close_ff_radius`). 설정이 하나뿐이고 플러그인 이름이 곧 그 설정이면 플러그인 이름 그대로(`l4d2_round_restart_delay`). `AutoExecConfig` 파일 이름은 플러그인 이름.
- enum 값: 이름 있는 enum은 `타입_값` (`MOTDTitle_Vanilla`), 이름 없는 상수 enum은 `UPPER_SNAKE` (`STAGE_IDLE`).
- 콜백 함수 접두어:

  | 등록 방법 | 접두어 | 예 |
  |---|---|---|
  | HookEvent | `Event_` | `Event_RoundStart` |
  | CreateTimer | `Timer_` | `Timer_CheckProgress` |
  | RegConsoleCmd / RegAdminCmd / AddCommandListener | `Cmd_` | `Cmd_Progress` |
  | ConVar.AddChangeHook | `ConVarChanged_` | `ConVarChanged_Update` |
  | RequestFrame | `Frame_` | `Frame_Notify` |
  | SDKHook | `Hook_` + 훅 종류 | `Hook_OnTakeDamage`, `Hook_SetTransmit` |
  | HookUserMessage | `MsgHook_` | `MsgHook_VGUIMenu` |
  | AddNormalSoundHook | `SoundHook_` | `SoundHook_Normal` |
  | TR_*Filter | `TraceFilter_` | `TraceFilter_NoPlayers` |
  | DHooks 콜백 | `DHook_` | `DHook_LeapOnTouch` |
  | hxlib AddEntityHook | `EntityHook_` | `EntityHook_RemoveAmmoPost` |
  | SMCParser | `SMC_` | `SMC_OnKeyValue` |
  | actions.ext 콜백 | `ActionHook_` | `ActionHook_OnStuck` |

## enum struct

- 함께 다니는 상태를 묶을 때만 쓴다. 배열 하나로 충분하면 쓰지 않는다.
- 타입 이름: PascalCase 명사 (`Despawner`, `SoundParser`)
- 멤버 필드: 지역변수와 같은 규칙. 헝가리안·타입 이름 접두어 없이 lowerCamelCase (`bufferLen`, `entRef`)
- 메서드: PascalCase 동사 (`Update`, `Play`). 초기화 메서드는 `Init`
- 내부 순서: 필드 → 빈 줄 → 메서드. 필드는 타입·이름을 정렬한다.
- 여러 개면 다른 struct가 쓰는 쪽을 먼저 둔다.
- 메서드 매개변수가 멤버 이름과 겹치면 다른 이름을 쓴다.

## myinfo

```
public Plugin myinfo =
{
    name        = "L4D2 ...",
    author      = "Rainy",
    description = "...합니다.",
    version     = "x.y.z",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/<rainy|archive>/<plugin>"
};
```

- author는 `Rainy`만 쓴다. description은 `~합니다.` 문장형.
