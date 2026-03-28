# L4D2 SourceMod

Rainy의 Left 4 Dead 2 SourceMod 구성 모음입니다.

## 설치

> 주의: 아래 방법은 저의 게임 환경과 똑같이 설정할 사람만 사용하세요.

1. 컴퓨터에 Python이 설치되어 있어야 합니다.  
   없다면 [Miniconda](https://www.anaconda.com/docs/getting-started/miniconda/install#windows-installation)를 설치하세요.

2. `L4D2_설치경로.ini` 파일에 레포데2 설치 경로를 입력합니다.  
   설치 경로는 아래 과정으로 얻을 수 있습니다.  
   참고: 설치 경로에는 `left4dead2.exe`가 존재합니다.

   ```text
   Steam 라이브러리에서 Left 4 Dead 2를 우클릭 → 속성 → 설치된 파일 → 로컬 파일 탐색 클릭
   ```

3. API와 플러그인을 설치합니다.  
   이때 플러그인은 소스파일(.sp)만 복사되며, 컴파일을 해야합니다.

   ```powershell
   python 01_install.py
   ```

4. 플러그인을 컴파일합니다.  
   컴파일된 결과물(.smx)은 자동으로 `sourcemod/plugins` 폴더로 이동됩니다.

   ```powershell
   python 02_compile.py
   ```

## 삭제

API, 플러그인을 모두 삭제합니다.

```powershell
python 03_uninstall.py
```

## API

1. SourceMod  
   <https://www.sourcemod.net/downloads.php?branch=stable>

2. Metamod  
   <https://www.sourcemm.net/downloads.php?branch=stable>

## 플러그인 목록

### A. 자작 플러그인

1. [dingshot](/Archive/dingshot/)  
   헤드샷 시 띵 소리를 출력합니다.

2. [l4d2_accuracy_stat_fix](/Plugin/l4d2_accuracy_stat_fix/)  
   근접무기와 전기톱을 명중률 통계에서 제외합니다.

3. [l4d2_block_idle](/Archive/l4d2_block_idle/)  
   유휴 모드를 차단합니다.

4. [l4d2_block_thirdperson](/Archive/l4d2_block_thirdperson/)  
   3인칭 모드를 차단합니다.

5. [l4d2_fix_si_sound](/Plugin/l4d2_fix_si_sound/)  
   특수좀비의 무음 문제를 개선합니다. (공개 플러그인 합본)

6. [l4d2_getup_damage_fix](/Plugin/l4d2_getup_damage_fix/)  
   일어나는 애니메이션이 진행되는 동안의 무적타임 불일치 문제를 고칩니다.

7. [l4d2_hide_idle_message](/Plugin/l4d2_hide_idle_message/)  
   유휴 상태 메시지를 채팅창에 표시하지 않도록 합니다.

8. [l4d2_idle_adrenaline_fix](/Plugin/l4d2_idle_adrenaline_fix/)  
   플레이어가 유휴 모드에서 복귀할 때 아드레날린 효과를 유지하도록 수정합니다.

9. [l4d2_idle_fix](/Plugin/l4d2_idle_fix)  
   유휴 명령 미인식 문제를 해결합니다.

10. [l4d2_idle_flashlight_fix](/Plugin/l4d2_idle_flashlight_fix/)  
    유휴 전 손전등 on/off 상태를 유휴 후에도 유지합니다.

11. [l4d2_idle_reload_on_all_weapons](/Plugin/l4d2_idle_reload_on_all_weapons/)  
    모든 무기에서 유휴 장전이 가능하도록 합니다.

12. [l4d2_ragdoll_vanish](/Plugin/l4d2_ragdoll_vanish/)  
    CI/SI의 ragdoll을 즉시 제거합니다.

13. [l4d2_random_horde_notifier](/Plugin/l4d2_random_horde_notifier/)  
    랜덤 웨이브가 발생하면 알림을 표시합니다.

14. [l4d2_tank_props_glow](/Plugin/l4d2_tank_props_glow/)  
    탱크가 날릴 수 있는 물체에 글로우 효과를 줍니다.

15. [l4d2_tickrate_door_fix](/Plugin/l4d2_tickrate_door_fix/)  
    틱레이트 변경에 따른 문 속도 문제를 고칩니다.

### B. 공개 플러그인

1. drop_secondary (forward 추가)  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/drop_secondary>

2. l4d_witch_retreat_panic_fix  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d_witch_retreat_panic_fix>

3. l4d2_item_hint  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_item_hint>

4. l4d2_skill_detect  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_skill_detect>

5. l4dffannounce  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4dffannounce>

6. trigger_horde_notify  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/trigger_horde_notify>

7. firebulletsfix  
   <https://github.com/fbef0102/Sourcemod-Plugins/tree/main/firebulletsfix>

8. l4d_death_item_glow (보조무기 glow 추가)  
   <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_death_item_glow>

9. l4d_fix_common_shove  
   <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_fix_common_shove>

10. l4d_tongue_float_fix  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_tongue_float_fix>

11. l4d2_charge_target_fix  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_charge_target_fix>

12. l4d2_fix_jockey_hitbox (자키 bbox 버그, 밀치기 후 즉시 잡기 고침)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_fix_jockey_hitbox>

13. l4d_tank_damage_announce  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_tank_damage_announce.sp>

14. l4d_witch_damage_announce  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_witch_damage_announce.sp>

15. l4d2_jockey_jumpcap_patch (봇 제한 제거)  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d2_jockey_jumpcap_patch.sp>

16. Hunter_pounce_alignment_fix  
    <https://github.com/LuxLuma/Left-4-fix/tree/master/left%204%20fix/hunter/Hunter_pounce_alignment_fix>

17. spit_fizzle  
    <https://github.com/neburaii/l4d2-plugins/tree/main/spit_fizzle>

18. Explosion Announcer  
    <https://forums.alliedmods.net/showthread.php?t=328006>

19. Gear Transfer  
    <https://forums.alliedmods.net/showthread.php?t=137616>

20. l4d2_bugfix_deathspit  
    <https://forums.alliedmods.net/showthread.php?p=2827186>

21. l4d2_tickrate_sg552_fix  
    <https://forums.alliedmods.net/showthread.php?t=322141>

22. lagpreventor  
    <https://forums.alliedmods.net/showthread.php?p=2758895>

23. Shove Direction Fix  
    <https://forums.alliedmods.net/showthread.php?p=2675039>

24. Throwable Announcer  
    <https://forums.alliedmods.net/showthread.php?p=2719564>

25. Upgrade Ammo Pack Deploy Announce  
    <https://forums.alliedmods.net/showthread.php?p=2797826>

26. l4d2_kill_sound  
    출처 없음

### C. 종속 플러그인

1. Actions  
   <https://forums.alliedmods.net/showthread.php?p=2771520>

2. l4dtoolz  
   <https://github.com/accelerator74/l4dtoolz/releases>

3. Left4DHooks  
   <https://forums.alliedmods.net/showthread.php?t=321696>

4. Multi Colors  
   <https://github.com/fbef0102/L4D1_2-Plugins/releases/tag/Multi-Colors>

5. SourceScramble  
   <https://github.com/nosoop/SMExt-SourceScramble/releases>

6. Use Priority Patch  
   <https://forums.alliedmods.net/showthread.php?t=327511>

7. Tickrate Enabler  
   <https://github.com/accelerator74/Tickrate-Enabler>

### D. 보관 플러그인

1. [l4d2_idle_unlock](/Archive/l4d2_idle_unlock/)  
   플레이어 1명, 대전, 스캐빈지에서 유휴 모드가 가능하도록 합니다.  
   ([l4d2_idle_fix](/Plugin/l4d2_idle_fix)에 포함됨)

## Rainy's 리포지토리

- [l4d2-settings](https://github.com/rainy-me/l4d2-settings): Left 4 Dead 2 설정 모음
- [l4d2-sourcemod](https://github.com/rainy-me/l4d2-sourcemod): Left 4 Dead 2 SourceMod 구성 모음
