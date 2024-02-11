#include "SkyboxDefine.hlsl"

// Calculates the Rayleigh phase function
half getRayleighPhase(half eyeCos2)
{
    return 0.75 + 0.75 * eyeCos2;
}

half getRayleighPhase(half3 light, half3 ray)
{
    half eyeCos = dot(light, ray);
    return getRayleighPhase(eyeCos * eyeCos);
}

half scale(half inCos)
{
    half x = 1.0 - inCos;
    return 0.25 * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
}

// Calculates the Mie phase function
half getMiePhase(half eyeCos, half eyeCos2, half size)
{
    half temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;
    temp = pow(temp, pow(size, 0.65) * 10);
    temp = max(temp, 1.0e-4); // prevent division by zero, esp. in half precision
    temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
    #if defined(UNITY_COLORSPACE_GAMMA) && SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
        temp = pow(temp, .454545);
    #endif
    return temp;
}

// Calculates the sun shape
half calcSunAttenuation(half3 lightPos, half3 ray, half coverage, half size)
{
    half focusedEyeCos = pow(saturate(dot(lightPos, ray)), coverage);
    return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos, size);
}