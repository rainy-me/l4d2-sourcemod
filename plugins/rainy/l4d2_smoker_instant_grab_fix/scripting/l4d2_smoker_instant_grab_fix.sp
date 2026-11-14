#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sourcescramble>

#define GAMEDATA "l4d2_smoker_instant_grab_fix"

MemoryPatch g_hPatchMask;
MemoryPatch g_hPatchCollisionGroup;

public Plugin myinfo =
{
    name        = "L4D2 Smoker Instant Grab Fix",
    author      = "Rainy",
    description = "특정 물체 위에 서 있을 때 스모커에게 잡히면 즉시 조작이 불가능한 버그를 고칩니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_smoker_instant_grab_fix"
};

public void OnPluginStart()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "gamedata/%s.txt", GAMEDATA);
    if (FileExists(path) == false)
        SetFailState("Missing required file: %s", path);

    GameData gameData = new GameData(GAMEDATA);
    if (gameData == null)
        SetFailState("Failed to load %s.txt gamedata.", GAMEDATA);

    g_hPatchMask           = CreatePatch(gameData, "CTongue::UpdateAirChoke::FixTraceMask");
    g_hPatchCollisionGroup = CreatePatch(gameData, "CTongue::UpdateAirChoke::FixTraceCollisionGroup");

    delete gameData;

    // 둘 다 검증된 뒤에만 적용해서 한쪽만 패치된 상태를 막는다
    if (!g_hPatchMask.Enable())
        SetFailState("Failed to enable patch \"CTongue::UpdateAirChoke::FixTraceMask\".");
    if (!g_hPatchCollisionGroup.Enable())
        SetFailState("Failed to enable patch \"CTongue::UpdateAirChoke::FixTraceCollisionGroup\".");
}

MemoryPatch CreatePatch(GameData gameData, const char[] name)
{
    MemoryPatch patch = MemoryPatch.CreateFromConf(gameData, name);
    if (patch == null)
        SetFailState("Failed to create patch \"%s\".", name);
    if (!patch.Validate())
        SetFailState("Patch \"%s\" verify failed. Gamedata is outdated.", name);
    return patch;
}
