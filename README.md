# L4D2 SourceMod

Rainy의 Left 4 Dead 2 SourceMod 구성 모음입니다.

## 컴파일된 플러그인 모음

아래 링크에서 **최신** 컴파일 결과물(.smx 포함 전체 `Plugin` 폴더)을 zip으로 받을 수 있습니다.  
코드가 수정되면 컴파일 결과물도 자동으로 업데이트됩니다.

- 다운로드: [`rainy_plugins_sm1.12.zip`](https://github.com/rainy-me/l4d2-sourcemod/releases/download/latest/rainy_plugins_sm1.12.zip)
- 설치 방법: [`Youtube`](https://youtu.be/vSR5Lb6wTy8)

## 설치

> 주의: 아래 방법은 저의 게임 환경과 똑같이 설정할 사람만 사용하세요.

1. 컴퓨터에 Python이 설치되어 있어야 합니다.  
   없다면 [uv](https://docs.astral.sh/uv/getting-started/installation/)를 설치하세요.

2. `L4D2_설치경로.ini` 파일에 레포데2 설치 경로를 입력합니다.  
   설치 경로는 아래 과정으로 얻을 수 있습니다.  
   참고: 설치 경로에는 `left4dead2.exe`가 존재합니다.

   ```text
   Steam 라이브러리에서 Left 4 Dead 2를 우클릭 → 속성 → 설치된 파일 → 로컬 파일 탐색 클릭
   ```

3. API와 스크립트를 레포데2 설치 경로에 복사합니다.

   ```powershell
   uv run 01_copy.py
   ```

4. 스크립트를 컴파일합니다.  
   컴파일된 결과물(.smx)은 자동으로 `sourcemod/plugins` 폴더로 이동됩니다.

   ```powershell
   uv run 02_compile.py
   ```

## 삭제

API, 플러그인을 모두 삭제합니다.

```powershell
uv run 03_uninstall.py
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

2. [l4d2_accuracy_stat_fix](/Archive/l4d2_accuracy_stat_fix/)  
   근접무기와 전기톱을 명중률 통계에서 제외합니다.

3. [l4d2_ai_stagger_claw_fix](/Plugin/l4d2_ai_stagger_claw_fix/)  
   AI SI가 비틀거리거나 공중에 떠 있는 동안 긁기공격을 하지 못하도록 방지합니다.

4. [l4d2_block_idle](/Archive/l4d2_block_idle/)  
   유휴 모드를 차단합니다.

5. [l4d2_block_thirdperson](/Archive/l4d2_block_thirdperson/)  
   3인칭 모드를 차단합니다.

6. [l4d2_campaign_progress_notifier](/Plugin/l4d2_campaign_progress_notifier/)  
   캠페인 진행 상황을 알립니다.

7. [l4d2_charger_carry_ff_fix](/Plugin/l4d2_charger_carry_ff_fix/)  
   차저에게 끌려가는 생존자에 대한 팀킬을 방지합니다.

8. [l4d2_consistent_checkpoint_heal](/Plugin/l4d2_consistent_checkpoint_heal/)  
   맵 전환 시 생존자의 체력을 50까지 회복시키고, 무력화 효과를 제거합니다.

9. [l4d2_fast_map_transition](/Plugin/l4d2_fast_map_transition/)  
   다음 챕터로 넘어가는 데 걸리는 시간을 줄여줍니다.

10. [l4d2_fix_si_sound](/Plugin/l4d2_fix_si_sound/)  
    특수좀비의 무음 문제를 개선합니다.

11. [l4d2_getup_damage_fix](/Plugin/l4d2_getup_damage_fix/)  
    일어나는 애니메이션이 진행되는 동안의 무적타임 불일치 문제를 고칩니다.

12. [l4d2_hang_fall_death_defib_fix](/Plugin/l4d2_hang_fall_death_defib_fix/)  
    매달리는 중에 떨어져 사망한 생존자의 소생 불가 버그를 고칩니다.

13. [l4d2_hide_idle_message](/Plugin/l4d2_hide_idle_message/)  
    유휴 상태 메시지를 채팅창에 표시하지 않도록 합니다.

14. [l4d2_idle_adrenaline_fix](/Plugin/l4d2_idle_adrenaline_fix/)  
    플레이어가 유휴 모드에서 복귀할 때 아드레날린 효과를 유지하도록 합니다.

15. [l4d2_idle_fix](/Plugin/l4d2_idle_fix)  
    유휴 명령 미인식 문제를 해결합니다.

16. [l4d2_idle_flashlight_fix](/Plugin/l4d2_idle_flashlight_fix/)  
    유휴 전 손전등 on/off 상태를 유휴 후에도 유지합니다.

17. [l4d2_idle_reload_on_all_weapons](/Plugin/l4d2_idle_reload_on_all_weapons/)  
    모든 무기에서 유휴 장전이 가능하도록 합니다.

18. [l4d2_item_thrower](/Plugin/l4d2_item_thrower/)  
    들고 있는 무기/아이템을 앞으로 던집니다.

19. [l4d2_no_ci_melee_kill_collision](/Plugin/l4d2_no_ci_melee_kill_collision/)  
    근접무기로 죽인 일반좀비와의 충돌을 제거합니다.

20. [l4d2_no_close_ff](/Plugin/l4d2_no_close_ff/)  
    팀원이 너무 가까이 있을 때 팀킬을 차단합니다.

21. [l4d2_no_deathfall_cam](/Plugin/l4d2_no_deathfall_cam/)  
    추락 시 카메라 시점 전환을 차단합니다.

22. [l4d2_one_punch_shove](/Archive/l4d2_one_punch_shove/)  
    CI, SI를 밀치기 한 번으로 죽일 수 있습니다.

23. [l4d2_player_connect_notifier](/Plugin/l4d2_player_connect_notifier/)  
    플레이어가 서버에 접속하면 채팅창에 알립니다.

24. [l4d2_print_entity_info](/Archive/l4d2_print_entity_info/)  
    크로스헤어가 가리키는 엔티티의 상세 정보를 출력합니다.

25. [l4d2_quick_healing](/Plugin/l4d2_quick_healing/)  
    시작 은신처 내에서 1회 한정 킷을 즉시 사용할 수 있습니다.

26. [l4d2_ragdoll_vanish](/Plugin/l4d2_ragdoll_vanish/)  
    CI/SI의 ragdoll을 즉시 제거합니다.

27. [l4d2_rainy_server_assistant](/Plugin/l4d2_rainy_server_assistant/)  
    Rainy 서버 자동화 플러그인

28. [l4d2_reserve_ammo_multiplier](/Plugin/l4d2_reserve_ammo_multiplier/)  
    예비 탄약 소지량을 배율로 조정합니다.

29. [l4d2_skip_outtro](/Plugin/l4d2_skip_outtro/)  
    맵 클리어 시 아웃트로를 빠르게 건너뜁니다.

30. [l4d2_smoker_instant_grab_fix](/Archive/l4d2_smoker_instant_grab_fix/)  
    스모커가 worldspawn이 아닌 엔티티 위에 서 있는 생존자를 잡을 때 즉시 끌려가는 버그를 고칩니다.

31. [l4d2_tank_props_glow](/Plugin/l4d2_tank_props_glow/)  
    탱크가 날릴 수 있는 물체에 글로우 효과를 줍니다.

32. [l4d2_tank_witch_spawn_notifier](/Plugin/l4d2_tank_witch_spawn_notifier/)  
    탱크 및 윗치의 스폰을 알립니다.

33. [l4d2_tickrate_door_fix](/Plugin/l4d2_tickrate_door_fix/)  
    틱레이트 변경에 따른 문 속도 문제를 고칩니다.

34. [l4d2_welcome](/Plugin/l4d2_welcome/)  
    환영 인사와 서버 안내를 합니다.

### B. 공개 플러그인

1. charging_takedamage_patch  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/charging_takedamage_patch>

2. drop_secondary (forward 추가)  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/drop_secondary>

3. l4d_cutscene_nodamage  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d_cutscene_nodamage>

4. l4d_shotgun_sound_fix  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d_shotgun_sound_fix>

5. l4d_witch_retreat_panic_fix  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d_witch_retreat_panic_fix>

6. l4d2_item_hint  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_item_hint>

7. l4d2_skill_detect (full/chip level 수정)  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_skill_detect>

8. l4dffannounce (알림 문구 수정)  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4dffannounce>

9. LMC_Black_and_White_Notifier (알림 문구 수정)  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/LMC_Black_and_White_Notifier>

10. trigger_horde_notify  
    <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/trigger_horde_notify>

11. firebulletsfix  
    <https://github.com/fbef0102/Sourcemod-Plugins/tree/main/firebulletsfix>

12. l4d_death_item_glow (보조무기 glow 추가)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_death_item_glow>

13. l4d_fix_common_shove  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_fix_common_shove>

14. l4d_fix_stagger_dir  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_fix_stagger_dir>

15. l4d_lagcomp_skeet  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_lagcomp_skeet>

16. l4d_rock_invuln_duration (기본값 0 설정)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_rock_invuln_duration>

17. l4d_tank_damage_announce  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/blob/master/The%20Last%20Stand/l4d_tank_damage_announce>

18. l4d2_charge_target_fix  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_charge_target_fix>

19. l4d2_fix_jockey_hitbox (버그 고침)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_fix_jockey_hitbox>

20. l4d_witch_damage_announce  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_witch_damage_announce.sp>

21. l4d_skip_intro  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_skip_intro.sp>

22. l4d2_jockey_jumpcap_patch (봇 제한 제거, 밀치기 후 즉시 잡기 고침)  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d2_jockey_jumpcap_patch.sp>

23. l4d2_sg552_zoom_fix  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d2_sg552_zoom_fix.sp>

24. survivor_mvp (convar 기본값 수정)  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/survivor_mvp.sp>

25. hunter_audio_feedback  
    <https://github.com/neburaii/l4d2-plugins/tree/main/hunter_audio_feedback>

26. insta_smoke_fix  
    <https://github.com/neburaii/l4d2-plugins/tree/main/insta_smoke_fix>

27. motd_title (커스텀)  
    <https://github.com/neburaii/l4d2-plugins/tree/main/motd_title>

28. priority_sounds (탱크 data 제거)  
    <https://github.com/neburaii/l4d2-plugins/tree/main/priority_sounds>

29. round_restart_delay (convar 기본값 수정)  
    <https://github.com/neburaii/l4d2-plugins/tree/main/round_restart_delay>

30. spit_fizzle  
    <https://github.com/neburaii/l4d2-plugins/tree/main/spit_fizzle>

31. strict_despawn  
    <https://github.com/neburaii/l4d2-plugins/tree/main/strict_despawn>

32. Hunter_pounce_alignment_fix  
    <https://github.com/LuxLuma/Left-4-fix/tree/master/left%204%20fix/hunter/Hunter_pounce_alignment_fix>

33. l4d2_kill_sound  
    <https://github.com/Hatsune-Imagine/l4d2-plugins/tree/main/l4d2_kill_sound>

34. Explosion Announcer  
    <https://forums.alliedmods.net/showthread.php?t=328006>

35. Gear Transfer  
    <https://forums.alliedmods.net/showthread.php?t=137616>

36. l4d_path_to_goal  
    <https://forums.alliedmods.net/showthread.php?t=352685>

37. l4d2_bugfix_deathspit  
    <https://forums.alliedmods.net/showthread.php?p=2827186>

38. lagpreventor  
    <https://forums.alliedmods.net/showthread.php?p=2758895>

39. noteam_nudging  
    <https://forums.alliedmods.net/showthread.php?p=2758622>

40. Shove Direction Fix  
    <https://forums.alliedmods.net/showthread.php?p=2675039>

41. Throwable Announcer  
    <https://forums.alliedmods.net/showthread.php?p=2719564>

42. Upgrade Ammo Pack Deploy Announce  
    <https://forums.alliedmods.net/showthread.php?p=2797826>

43. weapon_give_no_auto_switch  
    <https://forums.alliedmods.net/showthread.php?t=341173>

### C. 종속 플러그인

1. Actions  
   <https://forums.alliedmods.net/showthread.php?p=2771520>

2. hxlib  
   <https://github.com/neburaii/l4d2-plugins/tree/main/hxlib>

3. l4d_heartbeat  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d_heartbeat>

4. l4dtoolz  
   <https://github.com/accelerator74/l4dtoolz/releases>

5. Left4DHooks  
   <https://forums.alliedmods.net/showthread.php?t=321696>

6. Multi Colors  
   <https://github.com/fbef0102/L4D1_2-Plugins/releases/tag/Multi-Colors>

7. SourceScramble  
   <https://github.com/nosoop/SMExt-SourceScramble/releases>

8. Use Priority Patch  
   <https://forums.alliedmods.net/showthread.php?t=327511>

9. ThirdPersonShoulder_Detect  
   <https://forums.alliedmods.net/showthread.php?t=298649>

10. Tickrate Enabler  
    <https://github.com/accelerator74/Tickrate-Enabler/releases>

## Rainy's 리포지토리

- [l4d2-settings](https://github.com/rainy-me/l4d2-settings): Left 4 Dead 2 설정 모음
- [l4d2-sourcemod](https://github.com/rainy-me/l4d2-sourcemod): Left 4 Dead 2 SourceMod 구성 모음
