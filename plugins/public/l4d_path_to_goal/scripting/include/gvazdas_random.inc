#if defined _gvazdas_random_included
 #endinput
#endif
#define _gvazdas_random_included

#include <sourcemod>

// Generate random numbers seeded uniquely for each plugin.
// Avoids the predictable and spuriously correlated HL2 random number stream.

////////////////////////////////////////////////////////////////////////////////

// Random Floats //

// Returns a uniform random float in the range [min, max].
stock float GetRandomFloatV2(float min = 0.0, float max = 1.0, bool verify = false)
{
    if (min>=max)
    {
        //LogMessage("GetRandomFloatV2 %f>=%f, returning %f", min, max, min);
        return min;
    }
    if (min==0.0 && max==1.0) return GetURandomFloat();
    if (verify)
    {
        if (!IsFloatValid(min))
        {
            LogMessage("GetRandomFloatV2 bad min %f, returning max %f", min, max);
            return max;
        }
        if (!IsFloatValid(max))
        {
            LogMessage("GetRandomFloatV2 bad max %f, returning min %f", max, min);
            return min;
        }
    }
    float r = GetURandomFloat();
    float result = min*(1.0-r) + max*r;
    if (verify && !IsFloatValid(result))
    {
        LogMessage("GetRandomFloatV2 [%f %f] bad result %f, using HL2 stream", min, max, result);
        return GetRandomFloat(min,max);
    }
    if (result>=max) return max; // catching floating point errors
    if (result<=min) return min;
    return result;
}

// Return false if number is NaN, +inf or -inf.
stock bool IsFloatValid(float value)
{
    return (view_as<int>(value) & 0x7F800000) != 0x7F800000;
}

////////////////////////////////////////////////////////////////////////////////

// Random Integers //

// Returns a random integer in the range [min, max] using rejection sampling
stock int GetRandomIntV2(int min = 0, int max = 1)
{
    if (min>=max)
    {
        //LogMessage("GetRandomIntV2 %d>=%d, returning %d", min, max, min);
        return min;
    }
    int range = max-min;
    if (range<=0)
    {
        LogMessage("GetRandomIntV2 overflow, using HL2 stream");
        return GetRandomInt(min,max);
    }
    if (range==cellmax)
    {
        return min + GetURandomInt();
    }
    int choices = range + 1;
    int thresh = cellmax - (cellmax % choices + 1) % choices;
    int rand;
    do { rand = GetURandomInt() & cellmax; } while (rand > thresh);
    return min + (rand % choices);
}