#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <hxstocks>

#define MOTD_TITLE_LIBRARY "motd_title"
#define MAX_MOTD_TITLE_LEN 192
#define MAX_MOTD_LINE_LEN  256
#define MAX_USERMSG_LEN    255    // 유저 메시지 최대 크기

enum MOTDTitle
{
    MOTDTitle_Vanilla = 0,
    MOTDTitle_ConVar,
    MOTDTitle_Translation
};

// enum struct 메서드가 참조하므로 enum struct보다 앞에 둔다
/** convars */
ConVar     g_hConVarMOTDTitleType;
ConVar     g_hConVarMOTDTitle;

MOTDTitle  g_eMOTDTitleType;
char       g_sMOTDTitle[MAX_MOTD_TITLE_LEN];

enum struct MOTDBuffer
{
    int  flags;
    int  players[MAXPLAYERS_L4D2];
    int  playersRef[MAXPLAYERS_L4D2];
    int  playersNum;

    char buffer[MAX_USERMSG_LEN];
    int  bufferLen;
    bool overflow;

    /** returns false if the message does not fit; the caller must let the original through */
    bool Record(BfRead bf, const int[] clients, int clientsNum, bool reliable, bool init, char line[MAX_MOTD_LINE_LEN])
    {
        this.bufferLen = 0;
        this.overflow  = false;

        bool titleFound;
        int  totalKVIndex;

        this.AppendString("info");
        this.AppendByte(bf.ReadByte());                   // for formatting
        totalKVIndex = this.AppendByte(bf.ReadByte());    // total kayvalue pairs

        /** the remainder of the buffer are keyvalue pairs. it alternates, starting with a key, then a value */
        bool skipKV;
        for (bool key = true; bf.BytesLeft; key = !key)
        {
            bf.ReadString(line, sizeof(line), true);

            if (skipKV)
            {
                /** key being true here means we're at the key of the pair after the key that set skipKV to true */
                if (key)
                    skipKV = false;
                else
                    continue;
            }

            if (key && strcmp(line, "title") == 0)
            {
                skipKV     = true;
                titleFound = true;
                continue;
            }

            this.AppendString(line);
        }

        /** title key without value. value gets appended in post hook */
        this.AppendString("title");

        if (!titleFound)
            this.buffer[totalKVIndex] = view_as<int>(this.buffer[totalKVIndex]) + 1;

        this.flags = USERMSG_BLOCKHOOKS;
        if (reliable)
            this.flags |= USERMSG_RELIABLE;
        if (init)
            this.flags |= USERMSG_INITMSG;

        this.playersNum = clientsNum;

        for (int i = 0; i < clientsNum; i++)
        {
            this.players[i]    = clients[i];
            this.playersRef[i] = EntIndexToEntRef(clients[i]);
        }

        return !this.overflow;
    }

    void Send()
    {
        if (g_eMOTDTitleType == MOTDTitle_Vanilla)
            return;

        static char translatedTitle[MAX_MOTD_TITLE_LEN];
        int         recipient[1];

        for (int p = 0; p < this.playersNum; p++)
        {
            if (EntIndexToEntRef(this.players[p]) != this.playersRef[p])
                continue;

            recipient[0] = this.players[p];

            if (g_eMOTDTitleType == MOTDTitle_Translation)
            {
                FormatEx(translatedTitle, sizeof(translatedTitle), "%T", "#MOTD_Title", this.players[p]);
                this.SendUserMessage(recipient, 1, translatedTitle);
            }
            else
            {
                this.SendUserMessage(recipient, 1, g_sMOTDTitle);
            }
        }
    }

    /**********
     * helpers
     **********/

    void AppendString(const char[] str)
    {
        for (int i = 0;; i++)
        {
            if (this.AppendByte(str[i]) == -1 || str[i] == '\0')
                break;
        }
    }

    /** returns the index written to. -1 if the buffer is full */
    int AppendByte(int value)
    {
        /** leave at least 1 byte for the title's terminator */
        if (this.bufferLen >= MAX_USERMSG_LEN - 1)
        {
            this.overflow = true;
            return -1;
        }

        this.buffer[this.bufferLen++] = value;
        return this.bufferLen - 1;
    }

    void SendUserMessage(const int[] clients, int clientsNum, const char[] title)
    {
        BfWrite bf = view_as<BfWrite>(StartMessage("VGUIMenu", clients, clientsNum, this.flags));

        for (int i = 0; i < this.bufferLen; i++)
            bf.WriteByte(this.buffer[i]);

        /** cut the title to what is left of the message */
        char fit[MAX_MOTD_TITLE_LEN];
        int  maxLen = MAX_USERMSG_LEN - this.bufferLen;
        strcopy(fit, maxLen < sizeof(fit) ? maxLen : sizeof(fit), title);
        bf.WriteString(fit);

        EndMessage();
    }
}

MOTDBuffer g_esMotd;
ArrayList  g_hQueue;    // 같은 프레임에 여러 MOTD가 나가도 덮어쓰지 않도록 쌓아 둔다

public Plugin myinfo =
{
    name        = "L4D2 MOTD Title",
    author      = "Rainy",
    description = "MOTD 제목을 변경할 수 있도록 합니다.",
    version     = "1.0.1",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_motd_title"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    RegPluginLibrary(MOTD_TITLE_LIBRARY);
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hConVarMOTDTitleType = CreateConVar(
        "motd_title_type", "2",
        "source of the title string. 0 = vanilla | 1 = convar | 2 = SM translation (sourcemod/translations/l4d2_motd_title.phrases.txt)",
        FCVAR_NOTIFY);

    g_hConVarMOTDTitle = CreateConVar(
        "motd_title", "non-translated title",
        "title text that displays above motd html. only used if motd_title_type is set to 1",
        FCVAR_NOTIFY);

    g_hConVarMOTDTitleType.AddChangeHook(ConVarChanged_Read);
    g_hConVarMOTDTitle.AddChangeHook(ConVarChanged_Read);
    ReadConVars();

    LoadTranslations("l4d2_motd_title.phrases");

    g_hQueue = new ArrayList(sizeof(MOTDBuffer));

    HookUserMessage(GetUserMessageId("VGUIMenu"), MsgHook_VGUIMenu, true);
}

/**********
 * ConVars
 *********/

void ConVarChanged_Read(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ReadConVars();
}

void ReadConVars()
{
    g_eMOTDTitleType = view_as<MOTDTitle>(g_hConVarMOTDTitleType.IntValue);
    g_hConVarMOTDTitle.GetString(g_sMOTDTitle, sizeof(g_sMOTDTitle));
}

/**************
 * UserMessage
 *************/

Action MsgHook_VGUIMenu(UserMsg msg_id, BfRead bf, const int[] clients, int clientsNum, bool reliable, bool init)
{
    static char line[MAX_MOTD_LINE_LEN];

    if (g_eMOTDTitleType == MOTDTitle_Vanilla)
        return Plugin_Continue;

    bf.ReadString(line, sizeof(line), true);
    if (strcmp(line, "info") != 0)
        return Plugin_Continue;

    if (!g_esMotd.Record(bf, clients, clientsNum, reliable, init, line))
        return Plugin_Continue;

    g_hQueue.PushArray(g_esMotd);
    RequestFrame(SendNewMsg);

    return Plugin_Handled;
}

/*************************
 * record/send motd buffer
 ************************/

void SendNewMsg()
{
    for (int i = 0; i < g_hQueue.Length; i++)
    {
        g_hQueue.GetArray(i, g_esMotd);
        g_esMotd.Send();
    }
    g_hQueue.Clear();
}
