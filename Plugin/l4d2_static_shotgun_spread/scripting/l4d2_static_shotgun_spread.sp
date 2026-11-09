#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d_pellet_spread_customizer>

// 링 하나에 들어가는 펠릿 수
#define RING_SIZE     3

// 첫 펠릿을 패턴 중심에 발사할지 여부
#define CENTER_PELLET 1

public Plugin myinfo =
{
    name        = "L4D2 Static Shotgun Spread",
    author      = "Rainy",
    description = "샷건 펠릿을 바닐라 위력에 맞춘 고정 링 패턴으로 발사합니다.",
    version     = "1.0.0",
    url         = "https://github.com/rainy-me/l4d2-sourcemod/tree/main/Plugin/l4d2_static_shotgun_spread"
};

public Action L4D_OnPelletFirstBullet(int weapon)
{
#if CENTER_PELLET
    return Plugin_Continue;
#else
    return Plugin_Handled;
#endif
}

// nPellet이 0부터든 1부터든 % 연산으로 0 ~ nMaxPellets-1 슬롯이 한 번씩 나온다.
// 거리/방향 포워드가 같은 nPellet을 받으므로 둘이 같은 링 위치를 얻는다.
void GetRingSlot(int nPellet, int nMaxPellets, int &ring, int &index, int &count)
{
    int slot = nPellet % nMaxPellets;
    ring     = slot / RING_SIZE;
    index    = slot % RING_SIZE;
    count    = nMaxPellets - ring * RING_SIZE;    // 마지막 링은 RING_SIZE보다 적을 수 있다.
    if (count > RING_SIZE)
    {
        count = RING_SIZE;
    }
}

public Action L4D_OnPelletSpread(int weapon, float &spread, int nPellet, int nMaxPellets)
{
    if (nMaxPellets <= 0)
    {
        return Plugin_Continue;
    }

    int ring, index, count;
    GetRingSlot(nPellet, nMaxPellets, ring, index, count);

    // spread는 최대 퍼짐값으로 들어온다. 바닐라 거리는 [0, max] 균등분포이므로
    // 각 링을 그 링의 펠릿들이 맡는 구간의 한가운데에 두어 거리별 평균 위력을 맞춘다.
    spread *= (ring * RING_SIZE + count * 0.5) / nMaxPellets;
    return Plugin_Changed;
}

public Action L4D_OnPelletSpreadDir(int weapon, float &angle, int nPellet, int nMaxPellets)
{
    if (nMaxPellets <= 0)
    {
        return Plugin_Continue;
    }

    int ring, index, count;
    GetRingSlot(nPellet, nMaxPellets, ring, index, count);
    int   numRings = (nMaxPellets + RING_SIZE - 1) / RING_SIZE;

    // 링 안은 등간격, 링마다 조금씩 돌려 펠릿끼리 방향이 겹치지 않게 한다.
    float deg      = 360.0 * index / count + 360.0 / RING_SIZE * ring / numRings;

    // 게임은 각도 0~180을 한 바퀴(360도)로 쓴다. (visualise_impacts로 확인)
    angle          = deg / 2.0;
    return Plugin_Changed;
}
