# 자작 플러그인 코드 스타일

자작 플러그인(`plugins/rainy`, `plugins/archive`)의 `<plugin>/scripting/<plugin>.sp`에 적용한다.

## 파일 순서

1. `#pragma semicolon 1` / `#pragma newdecls required`
2. `#include` (sourcemod → sdktools/sdkhooks 등 기본 → 외부 라이브러리)
3. `#define`, 그 뒤에 enum / enum struct / methodmap 같은 타입 정의
4. 전역 변수
5. `public Plugin myinfo`
6. `public void OnPluginStart()` (`AskPluginLoad2`가 있으면 그 바로 앞)
7. 함수들 (forward, 이벤트, 훅 콜백, 명령, 타이머)
8. 헬퍼 함수들 (IsClient 같은 범용 보조 함수) — 파일 맨 끝

- 플러그인 전용 함수(ReadConVars 등)는 헬퍼가 아니라 함수 영역에 둔다.
- enum struct 메서드가 전역을 참조하면 그 전역만 enum struct 앞에 둔다(뒤에 두면 컴파일 에러).

## public

- `public`은 꼭 필요한 곳에만 단다: `myinfo`, 그리고 이름으로 호출되는 forward(OnPluginStart, OnMapStart, OnClientPutInServer, AskPluginLoad2, left4dhooks의 L4D_On*/L4D2_On* 등 include에 `forward`로 선언된 것).
- 이벤트·타이머·SDKHook·명령·ConVar 변경·DHook·RequestFrame 콜백처럼 함수 참조로 넘기는 함수에는 달지 않는다.
- forward에서 `public`을 빼면 컴파일 에러 없이 호출만 안 되므로, 뺄 때는 include의 `forward` 선언 여부를 확인한다.

## 중괄호

- Allman 스타일, 들여쓰기 스페이스 4칸.
- if / else / for / while 본문이 한 줄 문장 하나면 중괄호를 쓰지 않고 다음 줄에 들여쓴다. `if (x) return;`처럼 같은 줄에 쓰지 않는다.
  ```
  if (!IsClientInGame(client))
      return;
  ```
- 가독성을 위해 중괄호를 유지하는 경우:
  - if / else if / else 체인 중 한 분기라도 여러 문장이면 체인 전체
  - 본문이 여러 줄에 걸치는 경우(조건이나 호출이 줄바꿈됨, for 본문이 중괄호 없는 if)
  - 본문에 주석 줄이 함께 있는 경우

## 이름

- 지역변수·매개변수: 헝가리안 접두어 없이 lowerCamelCase (`client`, `weapon`, `gameMode`). 멤버·전역·함수명과 겹치면 다른 의미 있는 이름을 쓴다.
  - `zClass`, `vPos`/`aPos`(victim/attacker)처럼 의미를 담은 접두어는 헝가리안이 아니다.
- 전역변수: `g_{type}{PascalCase}`, 접두어 뒤 밑줄 금지.
  - `i` int / `f` float / `b` bool / `s` char[] / `h` Handle 계열(ConVar, ArrayList, StringMap, DynamicHook, GameData 등) / `e` enum / `es` enum struct
  - 배열은 원소 타입 기준 (`float g_fPos[3]`)

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
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/<plugin>"
};
```

- author는 `Rainy`만 쓴다. description은 `~합니다.` 문장형.
