#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <hxstocks>

#define DATA_FILE "data/l4d2_priority_sounds.txt"

#define MIN_SUPPORTED_SNDCHAN SNDCHAN_WEAPON    // 1
#define MAX_SUPPORTED_SNDCHAN SNDCHAN_STREAM    // 5

PlayingSound g_esLastSound[MAXEDICTS + 1][MAX_SUPPORTED_SNDCHAN + 1];

StringMap   g_hMapSounds;
SoundParser g_esSoundParser;

/** prefix of sample names for networked messages. up to the first 2 characters can have these chars.
 * the client will process the sound using the name as it appears after these characters. */
enum
{
    SNDCHAR_STREAM         = '*',    // indicates streaming wav data
    SNDCHAR_USER_VOX       = '?',    // indicates user realtime voice data
    SNDCHAR_SENTENCE       = '!',    // indicates sentence wav
    SNDCHAR_DRY_MIX        = '#',    // indicates wav bypasses dsp fx
    SNDCHAR_DOPPLER        = '>',    // indicates doppler encoded stereo wav: left wav (incomming) and right wav (outgoing).
    SNDCHAR_DIRECTIONAL    = '<',    // indicates stereo wav has direction cone: mix left wav (front facing) with right wav (rear facing) based on soundfacing direction
    SNDCHAR_DIST_VARIANT   = '^',    // indicates distance variant encoded stereo wav (left is close, right is far)
    SNDCHAR_OMNI           = '@',    // indicates non-directional wav (default mono or stereo)
    SNDCHAR_HRTF           = '~',    // indicates wav should use HRTF spatialization for non-owners.
    SNDCHAR_RADIO          = '+',    // indicates a 'radio' sound -- should be played without spatialization
    SNDCHAR_SPATIAL_STEREO = ')',    // indicates spatialized stereo wav
    SNDCHAR_DIR_STEREO     = '(',    // indicates directional stereo wav (like doppler)
    SNDCHAR_FAST_PITCH     = '}',    // forces low quality, non-interpolated pitch shift
    SNDCHAR_SUBTITLED      = '$'     // indicates the subtitles are forced
}

/**********************
 * track playing sounds
 **********************/

enum struct Sound
{
    float duration;
    int   priority;
}

enum struct PlayingSound
{
    int    entRef;
    Handle timer;
    int    priority;

    void Init()
    {
        this.entRef = INVALID_ENT_REFERENCE;
        this.timer  = null;
    }

    Action Play(int entity, Sound soundData)
    {
        if (this.timer
            && EntRefToEntIndex(this.entRef) != INVALID_ENT_REFERENCE
            && soundData.priority < this.priority)
            return Plugin_Handled;

        if (this.timer)
            delete this.timer;

        if (soundData.priority)
        {
            this.priority = soundData.priority;
            this.entRef   = EntIndexToEntRef(entity);

            if (soundData.duration >= 0.1)
                this.timer = CreateTimer(soundData.duration, Timer_SoundFinish, this);
        }

        return Plugin_Continue;
    }
}

/******************
 * parse data file
 *****************/

enum ParserState
{
    Parser_LookingForSound,
    Parser_ReadingSound,
    Parser_Skip
};

enum struct SoundParser
{
    SMCParser   parser;
    ParserState state;
    ArrayList   stateHistory;

    Sound       sound;
    char        soundName[PLATFORM_MAX_PATH];

    void LoadSoundData()
    {
        char path[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, path, sizeof(path), DATA_FILE);
        if (!FileExists(path))
            return;

        this.parser                = new SMCParser();
        this.parser.OnEnterSection = SMC_OnEnterSound;
        this.parser.OnKeyValue     = INVALID_FUNCTION;
        this.parser.OnLeaveSection = SMC_OnLeaveSection;

        this.state                 = Parser_LookingForSound;
        this.stateHistory          = new ArrayList();

        this.parser.ParseFile(path);

        delete this.parser;
        delete this.stateHistory;
    }

    void SetState(ParserState state)
    {
        if (this.state == state)
            return;

        switch (state)
        {
            case Parser_LookingForSound:
            {
                this.parser.OnEnterSection = SMC_OnEnterSound;
                this.parser.OnKeyValue     = INVALID_FUNCTION;
            }
            case Parser_ReadingSound:
            {
                this.parser.OnEnterSection = SMC_OnSkipSection;
                this.parser.OnKeyValue     = SMC_OnKeyValue;
            }
            case Parser_Skip:
            {
                this.parser.OnEnterSection = SMC_OnSkipSection;
                this.parser.OnKeyValue     = INVALID_FUNCTION;
            }
        }

        this.state = state;
    }

    void OpenSound(const char[] name)
    {
        strcopy(this.soundName, sizeof(this.soundName), name);
        this.sound.duration = 0.0;
        this.sound.priority = 0;
    }

    void CommitSound()
    {
        g_hMapSounds.SetArray(this.soundName, this.sound, sizeof(this.sound));
    }

    SMCResult EnterSection(ParserState newState)
    {
        this.stateHistory.Push(this.state);
        this.SetState(newState);

        return SMCParse_Continue;
    }

    SMCResult LeaveSection()
    {
        int         newSize  = this.stateHistory.Length - 1;
        ParserState newState = this.stateHistory.Get(newSize);
        this.stateHistory.Resize(newSize);

        if (this.state == Parser_ReadingSound)
            this.CommitSound();

        this.SetState(newState);

        return SMCParse_Continue;
    }

    SMCResult Read(const char[] key, const char[] value)
    {
        if (strcmp(key, "duration") == 0)
        {
            float duration      = StringToFloat(value);
            this.sound.duration = duration;
        }
        else if (strcmp(key, "priority") == 0)
        {
            int priority        = StringToInt(value);
            this.sound.priority = priority;
        }

        return SMCParse_Continue;
    }
}

public Plugin myinfo =
{
    name        = "L4D2 Priority Sounds",
    author      = "Rainy",
    description = "우선순위가 높은 소리가 다른 소리에 끊기지 않게 합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/plugins/rainy/l4d2_priority_sounds"
};

public void OnPluginStart()
{
    g_hMapSounds = new StringMap();
    g_esSoundParser.LoadSoundData();

    for (int e = 0; e < sizeof(g_esLastSound); e++)
    {
        for (int c = MIN_SUPPORTED_SNDCHAN; c < sizeof(g_esLastSound[]); c++)
            g_esLastSound[e][c].Init();
    }

    AddNormalSoundHook(SoundHook_Normal);

    RegAdminCmd("sm_priority_si_sounds_reset", Cmd_Reset, ADMFLAG_ROOT);
}

Action Cmd_Reset(int client, int args)
{
    g_hMapSounds.Clear();
    g_esSoundParser.LoadSoundData();

    return Plugin_Handled;
}

void Timer_SoundFinish(Handle timer, PlayingSound sound)
{
    sound.timer = null;
}

Action SoundHook_Normal(int clients[64], int &numClients, char originalSample[PLATFORM_MAX_PATH], int &entity,
                        int &originalChannel, float &volume, int &level, int &pitch, int &flags, char soundEntry[256], int &seed)
{
    int channel = originalChannel;
    if (!IsValidEdict(entity) || !ProcessChannel(originalSample, channel))
        return Plugin_Continue;

    static char sample[sizeof(originalSample)];
    Sound       soundData;

    CorrectSample(originalSample, sample, sizeof(sample));
    if (!g_hMapSounds.GetArray(sample, soundData, sizeof(soundData)))
        soundData.priority = 0;

    return g_esLastSound[entity][channel].Play(entity, soundData);
}

SMCResult SMC_OnEnterSound(SMCParser parser, const char[] name, bool optQuotes)
{
    g_esSoundParser.OpenSound(name);
    return g_esSoundParser.EnterSection(Parser_ReadingSound);
}

SMCResult SMC_OnSkipSection(SMCParser parser, const char[] name, bool optQuotes)
{
    return g_esSoundParser.EnterSection(Parser_Skip);
}

SMCResult SMC_OnKeyValue(SMCParser parser, const char[] key, const char[] value, bool keyQuotes, bool valueQuotes)
{
    return g_esSoundParser.Read(key, value);
}

SMCResult SMC_OnLeaveSection(SMCParser parser)
{
    return g_esSoundParser.LeaveSection();
}

bool IsSoundChar(char c)
{
    return c == SNDCHAR_STREAM || c == SNDCHAR_USER_VOX
        || c == SNDCHAR_SENTENCE || c == SNDCHAR_DRY_MIX
        || c == SNDCHAR_DOPPLER || c == SNDCHAR_DIRECTIONAL
        || c == SNDCHAR_DIST_VARIANT || c == SNDCHAR_OMNI
        || c == SNDCHAR_HRTF || c == SNDCHAR_RADIO
        || c == SNDCHAR_SPATIAL_STEREO || c == SNDCHAR_DIR_STEREO
        || c == SNDCHAR_FAST_PITCH || c == SNDCHAR_SUBTITLED;
}

bool HasSoundChar(const char[] sample, char c)
{
    for (int i = 0; i < PLATFORM_MAX_PATH; i++)
    {
        if (!IsSoundChar(sample[i]))
            break;

        if (sample[i] == c)
            return true;
    }

    return false;
}

/**
 * correct channel to what it's expected to translate to client side.
 * returns true if this expected channel is targetted by the plugin.
 */
bool ProcessChannel(const char[] sample, int &channel)
{
    if (channel > 7)
        channel %= 8;

    if (channel != SNDCHAN_STREAM && channel != SNDCHAN_VOICE && channel != SNDCHAN_STATIC
        && HasSoundChar(sample, SNDCHAR_STREAM))
    {
        channel = SNDCHAN_STREAM;
        return true;
    }

    return MIN_SUPPORTED_SNDCHAN <= channel <= MAX_SUPPORTED_SNDCHAN;
}

void CorrectSample(const char[] original, char[] buffer, int bufferLen)
{
    int write = 0;
    for (int i = 0; write < bufferLen; i++)
    {
        if (!write && IsSoundChar(original[i]))
            continue;

        if (IsCharAlpha(original[i]))
            buffer[write++] = CharToLower(original[i]);
        else if (original[i] == '\\')
            buffer[write++] = '/';
        else
            buffer[write++] = original[i];

        if (original[i] == '\0')
            return;
    }
}
