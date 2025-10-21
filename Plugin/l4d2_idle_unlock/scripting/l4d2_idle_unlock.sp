#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name        = "L4D2 Idle Unlock",
    author      = "Rainy",
    description = "플레이어 1명, 대전, 스캐빈지에서 유휴 모드가 가능하도록 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/blob/main/Plugin/l4d2_idle_unlock"
};

Address    aGoAFK[4]               = { Address_Null, ... };
static int iOriginalBytes_GoAFK[8] = { -1, ... };
ConVar     g_hDirectorAFKTimeout   = null;

public void OnPluginStart()
{
    GameData gd_GoAFK = new GameData("l4d2_idle_unlock");
    if (gd_GoAFK == null)
    {
        SetFailState("Game Data Not Found!");
    }

    int iOffset_GoAFK;

    aGoAFK[0] = gd_GoAFK.GetAddress("PlayerPreThink");
    if (aGoAFK[0] != Address_Null)
    {
        aGoAFK[1]     = aGoAFK[0];

        iOffset_GoAFK = gd_GoAFK.GetOffset("PreThink_CompetitiveCondition");
        if (iOffset_GoAFK != -1)
        {
            if (LoadFromAddress(aGoAFK[0] + view_as<Address>(iOffset_GoAFK), NumberType_Int8) == 0x0F)
            {
                aGoAFK[0] += view_as<Address>(iOffset_GoAFK);

                for (int i = 0; i < 6; i++)
                {
                    iOriginalBytes_GoAFK[i] = LoadFromAddress(aGoAFK[0] + view_as<Address>(i), NumberType_Int8);
                    StoreToAddress(aGoAFK[0] + view_as<Address>(i), 0x90, NumberType_Int8);
                }

                PrintToServer("Idling Is Now Unrestricted!");
            }
            else
            {
                SetFailState("Offset \"PreThink_CompetitiveCondition\" Incorrect!");
            }
        }
        else
        {
            SetFailState("Offset \"PreThink_CompetitiveCondition\" Missing!");
        }

        iOffset_GoAFK = gd_GoAFK.GetOffset("PreThink_HumanSurvivorsCondition");
        if (iOffset_GoAFK != -1)
        {
            if (LoadFromAddress(aGoAFK[1] + view_as<Address>(iOffset_GoAFK), NumberType_Int8) == 0x01)
            {
                aGoAFK[1] += view_as<Address>(iOffset_GoAFK);
                StoreToAddress(aGoAFK[1], 0x00, NumberType_Int8);

                PrintToServer("Auto Idle Now Works Everytime!");
            }
            else
            {
                SetFailState("Offset \"PreThink_HumanSurvivorsCondition\" Incorrect!");
            }
        }
        else
        {
            SetFailState("Offset \"PreThink_HumanSurvivorsCondition\" Missing!");
        }
    }
    else
    {
        SetFailState("Address \"PlayerPreThink\" Missing!");
    }

    aGoAFK[2] = gd_GoAFK.GetAddress("PlayerGoingAFK");
    if (aGoAFK[2] != Address_Null)
    {
        aGoAFK[3]     = aGoAFK[2];

        iOffset_GoAFK = gd_GoAFK.GetOffset("GoAFKInput_CompetitiveCondition");
        if (iOffset_GoAFK != -1)
        {
            int iByte = LoadFromAddress(aGoAFK[2] + view_as<Address>(iOffset_GoAFK), NumberType_Int8);
            if (iByte == 0x75 || iByte == 0x74)
            {
                aGoAFK[2] += view_as<Address>(iOffset_GoAFK);

                for (int i = 0; i < 2; i++)
                {
                    iOriginalBytes_GoAFK[i + 6] = LoadFromAddress(aGoAFK[2] + view_as<Address>(i), NumberType_Int8);
                }

                StoreToAddress(aGoAFK[2], (iByte != 0x74) ? 0x90 : 0xEB, NumberType_Int8);
                if (iByte != 0x74)
                {
                    StoreToAddress(aGoAFK[2] + view_as<Address>(1), 0x90, NumberType_Int8);
                }

                PrintToServer("\"go_away_from_keyboard\" Is Now Unrestricted!");
            }
            else
            {
                SetFailState("Offset \"GoAFKInput_CompetitiveCondition\" Incorrect!");
            }
        }
        else
        {
            SetFailState("Offset \"GoAFKInput_CompetitiveCondition\" Missing!");
        }

        iOffset_GoAFK = gd_GoAFK.GetOffset("GoAFKInput_HumanSurvivorsCondition");
        if (iOffset_GoAFK != -1)
        {
            if (LoadFromAddress(aGoAFK[3] + view_as<Address>(iOffset_GoAFK), NumberType_Int8) == 0x01)
            {
                aGoAFK[3] += view_as<Address>(iOffset_GoAFK);
                StoreToAddress(aGoAFK[3], 0x00, NumberType_Int8);

                PrintToServer("\"go_away_from_keyboard\" Now Works Everytime!");
            }
            else
            {
                SetFailState("Offset \"GoAFKInput_HumanSurvivorsCondition\" Incorrect!");
            }
        }
        else
        {
            SetFailState("Offset \"GoAFKInput_HumanSurvivorsCondition\" Missing!");
        }
    }
    else
    {
        SetFailState("Address \"PlayerGoingAFK\" Missing!");
    }

    delete gd_GoAFK;

    g_hDirectorAFKTimeout = FindConVar("director_afk_timeout");
    if (g_hDirectorAFKTimeout == null)
    {
        SetFailState("Could not find ConVar 'director_afk_timeout'");
    }

    SetConVarInt(g_hDirectorAFKTimeout, 2147483647);
}

// 맵 로드 시에도 값을 유지
public void OnConfigsExecuted()
{
    if (g_hDirectorAFKTimeout != null)
    {
        SetConVarInt(g_hDirectorAFKTimeout, 2147483647);
    }
}

public void OnPluginEnd()
{
    if (aGoAFK[0] != Address_Null)
    {
        PrintToServer("Bringing Back Restriction Of Idling...");
        for (int i = 0; i < 6; i++)
        {
            StoreToAddress(aGoAFK[0] + view_as<Address>(i), iOriginalBytes_GoAFK[i], NumberType_Int8);
            iOriginalBytes_GoAFK[i] = -1;
        }
    }
    if (aGoAFK[1] != Address_Null)
    {
        PrintToServer("Restoring Original Behavior Of Auto Idle...");
        StoreToAddress(aGoAFK[1], 0x01, NumberType_Int8);
    }
    if (aGoAFK[2] != Address_Null)
    {
        PrintToServer("Bringing Back Restriction Of \"go_away_from_keyboard\"...");
        for (int i = 0; i < 2; i++)
        {
            StoreToAddress(aGoAFK[2] + view_as<Address>(i), iOriginalBytes_GoAFK[i + 6], NumberType_Int8);
            iOriginalBytes_GoAFK[i + 6] = -1;
        }
    }
    if (aGoAFK[3] != Address_Null)
    {
        PrintToServer("Restoring Original Behavior Of \"go_away_from_keyboard\"...");
        StoreToAddress(aGoAFK[3], 0x01, NumberType_Int8);
    }
}
