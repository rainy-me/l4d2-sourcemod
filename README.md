# L4D2 SourceMod

Rainy의 Left 4 Dead 2 SourceMod 구성 모음입니다.

## 컴파일된 플러그인 모음

아래 링크에서 **최신** 컴파일 결과물(.smx 포함 전체 `Plugin` 폴더)을 zip으로 받을 수 있습니다.  
코드가 수정되면 컴파일 결과물도 자동으로 업데이트됩니다.

- 다운로드: [`rainy_plugins_sm1.12.zip`](https://github.com/rainy-me/l4d2-sourcemod/releases/download/latest/rainy_plugins_sm1.12.zip)
- 설치 방법: [`Youtube`](https://youtu.be/vSR5Lb6wTy8)

## 개인 소장 플러그인 제작 (유료)

제가 제작하는 모든 플러그인은 공개를 원칙으로 합니다.  
공개하지 않고 개인적으로만 사용하실 플러그인은 유료로 제작해 드립니다.  
원하는 기능을 정리해서 [스팀 채팅](https://steamcommunity.com/id/rainy-me/)으로 문의해 주시면 제작 가능 여부와 비용을 안내해 드리겠습니다.

## API

1. SourceMod  
   <https://www.sourcemod.net/downloads.php?branch=stable>

2. Metamod  
   <https://www.sourcemm.net/downloads.php?branch=stable>

## 플러그인 목록

### A. 자작 플러그인

1. [l4d2_ai_stagger_claw_fix](/Plugin/l4d2_ai_stagger_claw_fix/)  
   AI SI가 비틀거리거나 공중에 떠 있는 동안 긁기공격을 하지 못하도록 방지합니다.

2. [l4d2_campaign_progress_notifier](/Plugin/l4d2_campaign_progress_notifier/)  
   캠페인 진행 상황을 알립니다.

3. [l4d2_charger_carry_ff_fix](/Plugin/l4d2_charger_carry_ff_fix/)  
   차저에게 끌려가는 생존자에 대한 팀킬을 방지합니다.

4. [l4d2_consistent_checkpoint_heal](/Plugin/l4d2_consistent_checkpoint_heal/)  
   맵 전환 시 생존자의 체력을 50까지 회복시키고, 무력화 효과를 제거합니다.

5. [l4d2_despawn_stuck_si](/Plugin/l4d2_despawn_stuck_si/)  
   끼인 특수좀비를 제거합니다.

6. [l4d2_fast_map_transition](/Plugin/l4d2_fast_map_transition/)  
   다음 챕터로 넘어가는 데 걸리는 시간을 줄여줍니다.

7. [l4d2_fix_si_sound](/Plugin/l4d2_fix_si_sound/)  
   특수좀비의 무음 문제를 개선합니다.

8. [l4d2_getup_damage_fix](/Plugin/l4d2_getup_damage_fix/)  
   일어나는 애니메이션이 진행되는 동안의 무적타임 불일치 문제를 고칩니다.

9. [l4d2_hang_fall_death_defib_fix](/Plugin/l4d2_hang_fall_death_defib_fix/)  
   매달리는 중에 떨어져 사망한 생존자의 소생 불가 버그를 고칩니다.

10. [l4d2_hide_idle_message](/Plugin/l4d2_hide_idle_message/)  
    유휴 상태 메시지를 채팅창에 표시하지 않도록 합니다.

11. [l4d2_hunter_audio_feedback](/Plugin/l4d2_hunter_audio_feedback/)  
    헌터가 도약할 때 항상 소리를 내도록 합니다.

12. [l4d2_idle_adrenaline_fix](/Plugin/l4d2_idle_adrenaline_fix/)  
    플레이어가 유휴 모드에서 복귀할 때 아드레날린 효과를 유지하도록 합니다.

13. [l4d2_idle_fix](/Plugin/l4d2_idle_fix)  
    유휴 명령 미인식 문제를 해결합니다.

14. [l4d2_idle_flashlight_fix](/Plugin/l4d2_idle_flashlight_fix/)  
    유휴 전 손전등 on/off 상태를 유휴 후에도 유지합니다.

15. [l4d2_idle_reload_on_all_weapons](/Plugin/l4d2_idle_reload_on_all_weapons/)  
    모든 무기에서 유휴 장전이 가능하도록 합니다.

16. [l4d2_item_thrower](/Plugin/l4d2_item_thrower/)  
    들고 있는 무기/아이템을 앞으로 던집니다.

17. [l4d2_motd_title](/Plugin/l4d2_motd_title/)  
    MOTD 제목을 변경할 수 있도록 합니다.

18. [l4d2_no_ci_melee_kill_collision](/Plugin/l4d2_no_ci_melee_kill_collision/)  
    근접무기로 죽인 일반좀비와의 충돌을 제거합니다.

19. [l4d2_no_close_ff](/Plugin/l4d2_no_close_ff/)  
    팀원이 너무 가까이 있을 때 팀킬을 차단합니다.

20. [l4d2_no_melee_ff](/Plugin/l4d2_no_melee_ff/)  
    근접무기 팀킬을 차단합니다.

21. [l4d2_no_si_fall_stagger_cancel](/Plugin/l4d2_no_si_fall_stagger_cancel/)  
    특수좀비가 낙하로 스태거를 취소하지 못하도록 착지 시 다시 스태거를 겁니다.

22. [l4d2_no_deathfall_cam](/Plugin/l4d2_no_deathfall_cam/)  
    추락 시 카메라 시점 전환을 차단합니다.

23. [l4d2_player_connect_notifier](/Plugin/l4d2_player_connect_notifier/)  
    플레이어가 서버에 접속하면 채팅창에 알립니다.

24. [l4d2_priority_sounds](/Plugin/l4d2_priority_sounds/)  
    중단되지 않는 우선순위 사운드를 설정합니다.

25. [l4d2_quick_healing](/Plugin/l4d2_quick_healing/)  
    시작 은신처 내에서 1회 한정 킷을 즉시 사용할 수 있습니다.

26. [l4d2_ragdoll_remover](/Plugin/l4d2_ragdoll_remover/)  
    CI/SI의 ragdoll을 즉시 제거합니다.

27. [l4d2_rainy_server_assistant](/Plugin/l4d2_rainy_server_assistant/)  
    Rainy 서버 자동화 플러그인

28. [l4d2_reserve_ammo_multiplier](/Plugin/l4d2_reserve_ammo_multiplier/)  
    예비 탄약 소지량을 배율로 조정합니다.

29. [l4d2_round_restart_delay](/Plugin/l4d2_round_restart_delay/)  
    라운드 재시작 지연 시간을 조정합니다.

30. [l4d2_skip_outtro](/Plugin/l4d2_skip_outtro/)  
    맵 클리어 시 아웃트로를 빠르게 건너뜁니다.

31. [l4d2_smoker_instant_grab_fix](/Plugin/l4d2_smoker_instant_grab_fix/)  
    특정 물체 위에 서 있을 때 스모커에게 잡히면 즉시 조작이 불가능한 버그를 고칩니다.

32. [l4d2_spit_fizzle](/Plugin/l4d2_spit_fizzle/)  
    스피터가 죽거나 비틀거리면 스핏 투사체가 사라집니다.

33. [l4d2_suicide](/Plugin/l4d2_suicide/)  
    어드민 권한 없이 !kill 또는 /kill 명령을 사용할 수 있도록 합니다.

34. [l4d2_tank_props_glow](/Plugin/l4d2_tank_props_glow/)  
    탱크가 날릴 수 있는 물체에 글로우 효과를 줍니다.

35. [l4d2_tank_witch_spawn_notifier](/Plugin/l4d2_tank_witch_spawn_notifier/)  
    탱크 및 윗치의 스폰을 알립니다.

36. [l4d2_tickrate_door_fix](/Plugin/l4d2_tickrate_door_fix/)  
    틱레이트 변경에 따른 문 속도 문제를 고칩니다.

### B. 자작 플러그인 (미사용)

1. [l4d2_accuracy_stat_fix](/Archive/l4d2_accuracy_stat_fix/)  
   근접무기와 전기톱을 명중률 통계에서 제외합니다.

2. [l4d2_block_idle](/Archive/l4d2_block_idle/)  
   유휴 모드를 차단합니다.

3. [l4d2_block_thirdperson](/Archive/l4d2_block_thirdperson/)  
   3인칭 모드를 차단합니다.

4. [l4d2_dingshot](/Archive/l4d2_dingshot/)  
   헤드샷 시 띵 소리를 출력합니다.

5. [l4d2_one_punch_shove](/Archive/l4d2_one_punch_shove/)  
   CI, SI를 밀치기 한 번으로 죽일 수 있습니다.

6. [l4d2_print_entity_info](/Archive/l4d2_print_entity_info/)  
   크로스헤어가 가리키는 엔티티의 상세 정보를 출력합니다.

### C. 공개 플러그인

이름 뒤 괄호는 원본에서 커스텀한 내용을 표시합니다. 괄호가 없으면 원본 그대로 사용합니다.

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

11. physics_object_pushfix  
    <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/physics_object_pushfix>

12. firebulletsfix  
    <https://github.com/fbef0102/Sourcemod-Plugins/tree/main/firebulletsfix>

13. l4d_death_item_glow (보조무기 glow 추가)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_death_item_glow>

14. l4d_fix_common_shove  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_fix_common_shove>

15. l4d_fix_stagger_dir  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_fix_stagger_dir>

16. l4d_lagcomp_skeet  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_lagcomp_skeet>

17. l4d_rock_invuln_duration (기본값 0 설정)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_rock_invuln_duration>

18. l4d_tank_damage_announce  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/blob/master/The%20Last%20Stand/l4d_tank_damage_announce>

19. l4d2_charge_target_fix  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_charge_target_fix>

20. l4d2_fix_jockey_hitbox (버그 고침)  
    <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d2_fix_jockey_hitbox>

21. l4d_witch_damage_announce  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_witch_damage_announce.sp>

22. l4d_skip_intro  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d_skip_intro.sp>

23. l4d2_jockey_jumpcap_patch (봇 제한 제거, 밀치기 후 즉시 잡기 고침)  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d2_jockey_jumpcap_patch.sp>

24. l4d2_sg552_zoom_fix  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/l4d2_sg552_zoom_fix.sp>

25. survivor_mvp (convar 기본값 수정)  
    <https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/survivor_mvp.sp>

26. Hunter_pounce_alignment_fix  
    <https://github.com/LuxLuma/Left-4-fix/tree/master/left%204%20fix/hunter/Hunter_pounce_alignment_fix>

27. l4d2_kill_sound  
    <https://github.com/Hatsune-Imagine/l4d2-plugins/tree/main/l4d2_kill_sound>

28. Explosion Announcer  
    <https://forums.alliedmods.net/showthread.php?t=328006>

29. Gear Transfer  
    <https://forums.alliedmods.net/showthread.php?t=137616>

30. l4d_path_to_goal  
    <https://forums.alliedmods.net/showthread.php?t=352685>

31. l4d2_bugfix_deathspit  
    <https://forums.alliedmods.net/showthread.php?p=2827186>

32. l4d2_pistol_reload_empty_fix  
    <https://forums.alliedmods.net/showthread.php?t=320496>

33. lagpreventor  
    <https://forums.alliedmods.net/showthread.php?p=2758895>

34. noteam_nudging  
    <https://forums.alliedmods.net/showthread.php?p=2758622>

35. Shove Direction Fix  
    <https://forums.alliedmods.net/showthread.php?p=2675039>

36. Throwable Announcer  
    <https://forums.alliedmods.net/showthread.php?p=2719564>

37. Upgrade Ammo Pack Deploy Announce  
    <https://forums.alliedmods.net/showthread.php?p=2797826>

38. weapon_give_no_auto_switch  
    <https://forums.alliedmods.net/showthread.php?t=341173>

### D. 종속 플러그인

1. [hxlib](/Plugin/hxlib/)

2. Actions  
   <https://forums.alliedmods.net/showthread.php?p=2771520>

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

9. ThirdPersonShoulder_Detect (유휴 복귀 후 3인칭 오감지 고침, TP_IsThirdPerson native 추가)  
   <https://forums.alliedmods.net/showthread.php?t=298649>

10. Tickrate Enabler  
    <https://github.com/accelerator74/Tickrate-Enabler/releases>

## Rainy's 리포지토리

- [l4d2-settings](https://github.com/rainy-me/l4d2-settings): Left 4 Dead 2 설정 모음
- [l4d2-sourcemod](https://github.com/rainy-me/l4d2-sourcemod): Left 4 Dead 2 SourceMod 구성 모음
