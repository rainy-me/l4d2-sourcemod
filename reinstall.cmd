xcopy /e /y "D:\SteamLibrary\steamapps\common\Left 4 Dead 2\left4dead2\addons\sourcemod\data\sqlite" "D:\repository\l4d2-settings\data\sqlite"
uv run 03_uninstall.py
uv run 01_copy.py
uv run 02_compile.py