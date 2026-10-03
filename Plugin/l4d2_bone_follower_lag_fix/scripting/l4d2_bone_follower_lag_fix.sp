#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "L4D2 Bone Follower Lag Fix",
	author = "Rainy",
	description = "감염자/생존자 모델의 phys_bone_follower를 제거하여 랙을 줄입니다.",
	version = "1.0.0",
	url = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_bone_follower_lag_fix"
};

public void OnEntityCreated(int entity, const char[] classname)
{
	// 모델은 생성 직후에 설정되므로 다음 프레임에 확인
	if(StrEqual(classname, "phys_bone_follower"))
		RequestFrame(KillCharacterBone, EntIndexToEntRef(entity));
}

// 감염자/생존자 모델을 장식용 prop_dynamic으로 쓰는 맵의 bone follower 제거
void KillCharacterBone(int ref)
{
	int entity = EntRefToEntIndex(ref);
	if(entity == INVALID_ENT_REFERENCE)
		return;

	char model[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
	if(strncmp(model, "models/infected/", 16, false) == 0 || strncmp(model, "models/survivors", 16, false) == 0)
		RemoveEntity(entity);
}
