#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>

#define THROW_SPEED       500.0
#define DEFIB_WORLD_MODEL "models/w_models/weapons/w_eq_defibrillator.mdl"

static const char g_sCarryables[][] = {
    "weapon_gascan",
    "weapon_propanetank",
    "weapon_oxygentank",
    "weapon_fireworkcrate",
    "weapon_gnome",
    "weapon_cola"
};

static const char g_sBombs[][] = {
    "weapon_pipe_bomb",
    "weapon_molotov",
    "weapon_vomitjar"
};

static const char g_sMisc[][] = {
    "weapon_first_aid_kit",
    "weapon_defibrillator",
    "weapon_upgradepack_explosive",
    "weapon_upgradepack_incendiary"
};

int g_iDefibModelIndex = -1;

public Plugin myinfo =
{
    name        = "L4D2 Item Thrower",
    author      = "Rainy",
    description = "들고 있는 무기/아이템을 앞으로 던집니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_item_thrower"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_throw", Cmd_Throw);
}

public void OnMapStart()
{
    g_iDefibModelIndex = PrecacheModel(DEFIB_WORLD_MODEL, true);
}

Action Cmd_Throw(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    ThrowItem(client);
    return Plugin_Handled;
}

void ThrowItem(int client)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1 || GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0)
    {
        return;
    }

    char weaponClass[64];
    GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
    if (StrEqual(weaponClass, "weapon_csbase_gun"))
    {
        return;
    }

    // 던질 위치/방향/속도 계산: 눈 위치에서 시선 방향으로 THROW_SPEED u/s + 플레이어 속도
    float pos[3], angles[3], fwd[3], velocity[3];
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    ScaleVector(fwd, THROW_SPEED);
    AddVectors(velocity, fwd, velocity);

    if (StrEqual(weaponClass, "weapon_pistol"))
    {
        // 쌍권총이면 한 자루를 분리해서 먼저 던집니다. (남은 한 자루는 아래에서 드랍)
        if (GetEntProp(weapon, Prop_Send, "m_isDualWielding") != 0)
        {
            SetEntProp(weapon, Prop_Send, "m_isDualWielding", 0);
            SetEntProp(weapon, Prop_Send, "m_hasDualWeapons", 0);

            int newClip = GetEntProp(weapon, Prop_Send, "m_iClip1") / 2;
            SetEntProp(weapon, Prop_Send, "m_iClip1", newClip);

            int secondPistol = CreateEntityByName("weapon_pistol");
            if (secondPistol != -1)
            {
                DispatchSpawn(secondPistol);
                SetEntProp(secondPistol, Prop_Send, "m_nSkin", GetEntProp(weapon, Prop_Send, "m_nSkin"));
                SetEntProp(secondPistol, Prop_Send, "m_iClip1", newClip);
                TeleportEntity(secondPistol, pos, angles, velocity);

                float pistolAngVel[3];
                GetRandomSpin(pistolAngVel);
                L4D_AngularVelocity(secondPistol, pistolAngVel);
            }
        }
    }
    else if (InClassList(weaponClass, g_sBombs, sizeof(g_sBombs)))
    {
        // 투척류: 던지는 모션 중(m_bRedraw)에는 버릴 수 없음
        if (GetEntProp(weapon, Prop_Send, "m_bRedraw") != 0)
        {
            return;
        }
    }
    else if (InClassList(weaponClass, g_sMisc, sizeof(g_sMisc)))
    {
        // 사용형 아이템: 사용 중(m_bPerformingAction)에는 버릴 수 없음
        if (GetEntProp(weapon, Prop_Send, "m_bPerformingAction") != 0)
        {
            return;
        }
    }
    else if (InClassList(weaponClass, g_sCarryables, sizeof(g_sCarryables)))
    {
        // 운반 아이템 제외 (이미 기본 공격으로 던질 수 있음)
        return;
    }

    // 무기를 손에서 분리해 월드 아이템으로 전환합니다.
    SDKHooks_DropWeapon(client, weapon);

    // 드랍된 제세동기의 월드 모델이 보이지 않는 문제를 보정합니다.
    if (StrEqual(weaponClass, "weapon_defibrillator") && g_iDefibModelIndex != -1)
    {
        SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", g_iDefibModelIndex);
    }

    // 근접 무기는 몸통 요(yaw) 기준으로 롤을 무작위로 틉니다.
    if (StrEqual(weaponClass, "weapon_melee"))
    {
        float bodyAngles[3];
        GetClientAbsAngles(client, bodyAngles);
        angles[1] = bodyAngles[1];
        angles[2] = float(GetRandomInt(-90, 90));
    }

    // 드랍된 무기를 눈 위치로 옮기고 시선 각도로 정렬한 뒤 시선 방향 속도를 부여해 던집니다.
    TeleportEntity(weapon, pos, angles, velocity);

    // Weapon_Drop이 추가한 기존 각속도를 제거한 뒤 의도한 스핀을 부여합니다.
    ZeroAngularVelocity(weapon);
    float angVel[3];
    GetRandomSpin(angVel);
    L4D_AngularVelocity(weapon, angVel);

    // 남은 예비 탄약을 무기에 실어 보내고 플레이어의 예비 탄약은 비웁니다.
    int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType >= 0 && HasEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo"))
    {
        int ammo = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
        SetEntProp(client, Prop_Send, "m_iAmmo", 0, _, ammoType);
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", ammo);
    }
}

void GetRandomSpin(float angVel[3])
{
    angVel[0] = float(GetRandomInt(-50, 50));
    angVel[1] = float(GetRandomInt(100, 200));
    angVel[2] = float(GetRandomInt(-20, 20));
}

void ZeroAngularVelocity(int entity)
{
    SetVariantString("self.ApplyLocalAngularVelocityImpulse(GetPhysAngularVelocity(self) * -1.0)");
    AcceptEntityInput(entity, "RunScriptCode");
}

bool InClassList(const char[] weaponClass, const char[][] list, int size)
{
    for (int i = 0; i < size; i++)
    {
        if (StrEqual(weaponClass, list[i]))
        {
            return true;
        }
    }
    return false;
}
