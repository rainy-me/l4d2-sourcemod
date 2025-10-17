# L4D2 SourceMod

Rainy의 Left 4 Dead 2 SourceMod 구성 모음입니다.

## 설치

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

API, 플러그인, sourcemod cfg를 모두 삭제합니다.

```powershell
python 03_uninstall.py
```

## API

1. SourceMod  
   <https://www.sourcemod.net/downloads.php?branch=stable>

2. Metamod  
   <https://www.sourcemm.net/downloads.php?branch=stable>

3. l4dtoolz  
   <https://github.com/accelerator74/l4dtoolz/releases>

## 플러그인 목록

### A. 자작 플러그인

1. [l4d2_hide_idle_message](/Plugin/l4d2_hide_idle_message)  
   유휴 상태 메시지를 채팅창에 표시하지 않습니다.

### B. 공개 플러그인

1. Tickrate Enabler  
   <https://forums.alliedmods.net/showthread.php?t=333408>

2. TickrateFixes (CVar 1.5 설정)  
   <https://github.com/fbef0102/Rotoblin-AZMod/blob/master/SourceCode/scripting-az/TickrateFixes.sp>

3. l4d2_item_hint  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_item_hint>

4. l4dffannounce  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4dffannounce>

5. trigger_horde_notify  
   <https://github.com/fbef0102/L4D1_2-Plugins/tree/master/trigger_horde_notify>

6. Throwable Announcer  
   <https://forums.alliedmods.net/showthread.php?p=2719564>

7. Explosion Announcer  
   <https://forums.alliedmods.net/showthread.php?t=328006>

8. l4d_death_item_glow (glow color 변경)  
   <https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/master/The%20Last%20Stand/l4d_death_item_glow>

### C. 종속 플러그인

1. SourceScramble  
   <https://github.com/nosoop/SMExt-SourceScramble/releases>

2. Use Priority Patch  
   <https://forums.alliedmods.net/showthread.php?t=327511>

3. Multi Colors  
   <https://github.com/fbef0102/L4D1_2-Plugins/releases/tag/Multi-Colors>

4. Left4DHooks  
   <https://forums.alliedmods.net/showthread.php?t=321696>
