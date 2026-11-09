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
// ring: 링 번호, index: 링 안 순서, count: 링 펠릿 수, start: 링 첫 슬롯
void GetRingSlot(int nPellet, int nMaxPellets, int &ring, int &index, int &count, int &start)
{
    int slot       = nPellet % nMaxPellets;

    // 마지막 링에 1발만 남으면 패턴이 한쪽으로 쏠리므로 마지막 두 링이 나눠 갖는다. (3+1 -> 2+2, RING_SIZE 3 이상 기준)
    int splitStart = nMaxPellets;
    if (nMaxPellets > RING_SIZE && nMaxPellets % RING_SIZE == 1)
    {
        splitStart = nMaxPellets - RING_SIZE - 1;
    }

    if (slot < splitStart)
    {
        ring  = slot / RING_SIZE;
        start = ring * RING_SIZE;
        count = nMaxPellets - start;    // 마지막 링은 RING_SIZE보다 적을 수 있다.
        if (count > RING_SIZE)
        {
            count = RING_SIZE;
        }
    }
    else
    {
        int first = (RING_SIZE + 1) / 2;
        ring      = splitStart / RING_SIZE;
        start     = splitStart;
        count     = first;
        if (slot - splitStart >= first)
        {
            ring++;
            start += first;
            count = RING_SIZE + 1 - first;
        }
    }

    index = slot - start;
}

public Action L4D_OnPelletSpread(int weapon, float &spread, int nPellet, int nMaxPellets)
{
    if (nMaxPellets <= 0)
    {
        return Plugin_Continue;
    }

    int ring, index, count, start;
    GetRingSlot(nPellet, nMaxPellets, ring, index, count, start);

    // spread는 최대 퍼짐값으로 들어온다. 바닐라 거리는 [0, max] 균등분포이므로
    // 각 링을 그 링의 펠릿들이 맡는 구간의 한가운데에 두어 거리별 평균 위력을 맞춘다.
    spread *= (start + count * 0.5) / nMaxPellets;
    return Plugin_Changed;
}

public Action L4D_OnPelletSpreadDir(int weapon, float &angle, int nPellet, int nMaxPellets)
{
    if (nMaxPellets <= 0)
    {
        return Plugin_Continue;
    }

    int ring, index, count, start;
    GetRingSlot(nPellet, nMaxPellets, ring, index, count, start);

    // 링 안은 등간격, 링마다 360/펠릿수씩 돌려 펠릿끼리 방향이 겹치지 않게 한다.
    float deg = 360.0 * index / count + 360.0 * ring / nMaxPellets;

    // 게임은 각도 0~180을 한 바퀴(360도)로 쓴다. (visualise_impacts로 확인)
    angle     = deg / 2.0;
    return Plugin_Changed;
}
