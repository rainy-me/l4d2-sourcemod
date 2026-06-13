#include <sourcemod>
#include <sdktools>
#include <colors>

public Plugin myinfo =
{
    name        = "L4D2 Print Entity Info",
    author      = "Rainy",
    description = "크로스헤어가 가리키는 엔티티의 상세 정보를 출력합니다.",
    version     = "1.1.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Archive/l4d2_print_entity_info"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_entinfo", Cmd_EntInfo);
}

Action Cmd_EntInfo(int client, int args)
{
    if (client < 1 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "Enter the command in the chat.");
        ReplyToCommand(client, "Shortcut key is convenient. (bind n \"say /entinfo\")");
        return Plugin_Handled;
    }

    int entity = GetClientAimTarget(client, false);
    if (entity < 0)
    {
        ReplyToCommand(client, "No entity is being aimed at.");
        return Plugin_Handled;
    }
    if (!IsValidEntity(entity))
    {
        ReplyToCommand(client, "Invalid entity: %d", entity);
        return Plugin_Handled;
    }

    PrintEntityInfo(client, entity);
    return Plugin_Handled;
}

void PrintEntityInfo(int client, int entity)
{
    // Classname
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    // Network class (DT class)
    char netclass[64] = "N/A";
    GetEntityNetClass(entity, netclass, sizeof(netclass));

    // Targetname
    char targetname[128];
    if (HasEntProp(entity, Prop_Data, "m_iName"))
        GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
    if (targetname[0] == '\0')
        strcopy(targetname, sizeof(targetname), "None");

    // Model path
    char model[PLATFORM_MAX_PATH];
    if (HasEntProp(entity, Prop_Data, "m_ModelName"))
        GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
    if (model[0] == '\0')
        strcopy(model, sizeof(model), "None");

    // Origin coordinates
    float origin[3];
    if (HasEntProp(entity, Prop_Send, "m_vecOrigin"))
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
    else
        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", origin);

    // Distance (Player eye position -> Entity coordinates)
    float eyePos[3];
    GetClientEyePosition(client, eyePos);
    float dist      = GetVectorDistance(eyePos, origin);

    // HP
    int   health    = -1;
    int   maxHealth = -1;
    if (HasEntProp(entity, Prop_Data, "m_iHealth"))
        health = GetEntProp(entity, Prop_Data, "m_iHealth");
    if (HasEntProp(entity, Prop_Data, "m_iMaxHealth"))
        maxHealth = GetEntProp(entity, Prop_Data, "m_iMaxHealth");

    // Print info
    CReplyToCommand(client, "---------------------------- Entity Info ----------------------------");
    CReplyToCommand(client, "{green}Index{default} : %d", entity);
    CReplyToCommand(client, "{green}Classname{default} : %s", classname);
    CReplyToCommand(client, "{green}NetClass{default} : %s", netclass);
    CReplyToCommand(client, "{green}Targetname{default} : %s", targetname);
    CReplyToCommand(client, "{green}Model{default} : %s", model);
    CReplyToCommand(client, "{green}Origin{default} : %.1f %.1f %.1f", origin[0], origin[1], origin[2]);
    CReplyToCommand(client, "{green}Distance{default} : %.1f units", dist);
    if (health >= 0)
    {
        if (maxHealth > 0)
            CReplyToCommand(client, "{green}HP{default} : %d / %d", health, maxHealth);
        else
            CReplyToCommand(client, "{green}HP{default} : %d", health);
    }
    if (entity >= 1 && entity <= MaxClients && IsClientInGame(entity))
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(entity, name, sizeof(name));
        CReplyToCommand(client, "{green}Player{default} : %s (Team %d)", name, GetClientTeam(entity));
    }
}
