#include <sourcemod>

public Plugin myinfo = {
	name = "[L4D2] a2s fix",
	author = "lakwsh",
	version = "1.0.2"
}

Address g_pPatch;
bool g_bWin;
int g_iOrig[2];

public void Patch(Address ptr, bool isWin)
{
	g_bWin = isWin;
	if(isWin) {
		g_iOrig[0] = LoadFromAddress(ptr, NumberType_Int16);
		int op = g_iOrig[0] & 0xFF;
		if(op != 0x74 && op != 0x90) SetFailState("'a2s_fix_w' offset broken."); // jz short, or already patched
		g_pPatch = ptr;
		StoreToAddress(ptr, 0x9090, NumberType_Int16, true);
		return;
	}
	g_pPatch = view_as<Address>(view_as<int>(ptr)+9);
	g_iOrig[0] = LoadFromAddress(g_pPatch, NumberType_Int32);
	g_iOrig[1] = LoadFromAddress(view_as<Address>(view_as<int>(ptr)+13), NumberType_Int16);
	StoreToAddress(g_pPatch, 0x90909090, NumberType_Int32, true);
	StoreToAddress(view_as<Address>(view_as<int>(ptr)+13), 0x9090, NumberType_Int16);
}

// restore, otherwise the linux signature no longer matches on reload
public void OnPluginEnd()
{
	if(!g_pPatch) return;
	if(g_bWin) {
		StoreToAddress(g_pPatch, g_iOrig[0], NumberType_Int16, true);
		return;
	}
	StoreToAddress(g_pPatch, g_iOrig[0], NumberType_Int32, true);
	StoreToAddress(view_as<Address>(view_as<int>(g_pPatch)+4), g_iOrig[1], NumberType_Int16);
}

public void OnPluginStart()
{
	FindConVar("sv_enableoldqueries").IntValue = 1;
	GameData hGameData = new GameData("l4d2_a2s_fix");
	if(!hGameData) SetFailState("Failed to load 'l4d2_a2s_fix.txt' gamedata.");
	Address ptr = hGameData.GetMemSig("a2s_fix");
	bool isWin = !ptr;
	if(isWin) ptr = hGameData.GetAddress("a2s_fix_w");
	if(!ptr) SetFailState("'a2s_fix' Signature broken.");
	Patch(ptr, isWin);
	CloseHandle(hGameData);
}