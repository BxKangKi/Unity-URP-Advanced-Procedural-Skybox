#include "SkyboxUtility.hlsl"

half3x3 CalculateSkybox(half3 vertex, half3 direction, half atmosphereThickness, half3 skyColor,
                            half3 groundColor, half3 sunColor, half exposure, half size, half coverage)
{
    half3 kSkyTintInGammaSpace = COLOR_2_GAMMA(skyColor); // convert tint from Linear back to Gamma
    half3 kScatteringWavelength = lerp (
        kDefaultScatteringWavelength-kVariableRangeForScatteringWavelength,
        kDefaultScatteringWavelength+kVariableRangeForScatteringWavelength,
        half3(1,1,1) - kSkyTintInGammaSpace); // using Tint in sRGB gamma allows for more visually linear interpolation and to keep (.5) at (128, gray in sRGB) point
    half3 kInvWavelength = 1.0 / pow(kScatteringWavelength, 4);

    half kKrESun = lerp(0.0, 0.0025, pow(atmosphereThickness, 2.5)) * kSUN_BRIGHTNESS;
    half kKr4PI = lerp(0.0, 0.0025, pow(atmosphereThickness, 2.5)) * 4.0 * 3.14159265;

    half3 cameraPos = half3(0,kInnerRadius + kCameraHeight,0);    // The camera's current position

    // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
    half3 eyeRay = normalize(mul((half3x3)unity_ObjectToWorld, vertex.xyz));

    half far = 0.0;
    half3 cIn, cOut;

    if (eyeRay.y >= 0.0)
    {
        // Sky
        // Calculate the length of the "atmosphere"
        far = sqrt(kOuterRadius2 + kInnerRadius2 * eyeRay.y * eyeRay.y - kInnerRadius2) - kInnerRadius * eyeRay.y;

        half3 pos = cameraPos + far * eyeRay;

        // Calculate the ray's starting position, then calculate its scattering offset
        half height = kInnerRadius + kCameraHeight;
        half depth = exp(kScaleOverScaleDepth * (-kCameraHeight));
        half startAngle = dot(eyeRay, cameraPos) / height;
        half startOffset = depth*scale(startAngle);


        // Initialize the scattering loop variables
        half sampleLength = far / kSamples;
        half scaledLength = sampleLength * kScale;
        half3 sampleRay = eyeRay * sampleLength;
        half3 samplePoint = cameraPos + sampleRay * 0.5;

        // Now loop through the sample rays
        half3 frontColor = half3(0.0, 0.0, 0.0);
        // Weird workaround: WP8 and desktop FL_9_3 do not like the for loop here
        // (but an almost identical loop is perfectly fine in the ground calculations below)
        // Just unrolling this manually seems to make everything fine again.
        {
            half height = length(samplePoint);
            half depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            half lightAngle = dot(direction.xyz, samplePoint) / height;
            half cameraAngle = dot(eyeRay, samplePoint) / height;
            half scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
            half3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

            frontColor += attenuate * (depth * scaledLength);
            samplePoint += sampleRay;
        }
        {
            half height = length(samplePoint);
            half depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            half lightAngle = dot(direction.xyz, samplePoint) / height;
            half cameraAngle = dot(eyeRay, samplePoint) / height;
            half scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
            half3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

            frontColor += attenuate * (depth * scaledLength);
            samplePoint += sampleRay;
        }



        // Finally, scale the Mie and Rayleigh colors and set up the varying variables for the pixel shader
        cIn = frontColor * (kInvWavelength * kKrESun);
        cOut = frontColor * kKmESun;
    }
    else
    {
        // Ground
        far = (-kCameraHeight) / (min(-0.001, eyeRay.y));

        half3 pos = cameraPos + far * eyeRay;

        // Calculate the ray's starting position, then calculate its scattering offset
        half depth = exp((-kCameraHeight) * (1.0/kScaleDepth));
        half cameraAngle = dot(-eyeRay, pos);
        half lightAngle = dot(direction.xyz, pos);
        half cameraScale = scale(cameraAngle);
        half lightScale = scale(lightAngle);
        half cameraOffset = depth*cameraScale;
        half temp = (lightScale + cameraScale);

        // Initialize the scattering loop variables
        half sampleLength = far / kSamples;
        half scaledLength = sampleLength * kScale;
        half3 sampleRay = eyeRay * sampleLength;
        half3 samplePoint = cameraPos + sampleRay * 0.5;

        // Now loop through the sample rays
        half3 frontColor = half3(0.0, 0.0, 0.0);
        half3 attenuate;
        {
            half height = length(samplePoint);
            half depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            half scatter = depth * temp - cameraOffset;
            attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));
            frontColor += attenuate * (depth * scaledLength);
            samplePoint += sampleRay;
        }

        cIn = frontColor * (kInvWavelength * kKrESun + kKmESun);
        cOut = clamp(attenuate, 0.0, 1.0);
    }

    vertex = -eyeRay;

    // if we want to calculate color in vprog:
    // 1. in case of linear: multiply by _Exposure in here (even in case of lerp it will be common multiplier, so we can skip mul in fshader)
    // 2. in case of gamma and SKYBOX_COLOR_IN_TARGET_COLOR_SPACE: do sqrt right away instead of doing that in fshader

    groundColor = exposure * (cIn + COLOR_2_LINEAR(groundColor) * cOut);
    skyColor = exposure * (cIn * getRayleighPhase(direction.xyz, -eyeRay));

    half lightColorIntensity = clamp(length(sunColor.xyz), 0.25, 1);
    sunColor = kHDSundiskIntensityFactor * saturate(cOut) * sunColor.xyz / lightColorIntensity;

#if defined(UNITY_COLORSPACE_GAMMA) && SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
    groundColor = sqrt(groundColor);
    skyColor = sqrt(skyColor);
    sunColor = sqrt(sunColor);
#endif
    // if y > 1 [eyeRay.y < -SKY_GROUND_THRESHOLD] - ground
    // if y >= 0 and < 1 [eyeRay.y <= 0 and > -SKY_GROUND_THRESHOLD] - horizon
    // if y < 0 [eyeRay.y > 0] - sky
    half3 ray = normalize(vertex.xyz);
    half y = ray.y / SKY_GROUND_THRESHOLD;
    // if we did precalculate color in vprog: just do lerp between them
    half3 col = lerp(skyColor, groundColor, saturate(y));

    if (y < 0.0)
    {
        sunColor = sunColor * calcSunAttenuation(direction.xyz, -ray, coverage, size);
    }
    else
    {
        sunColor = half3(0.0, 0.0, 0.0);
    }

    #if defined(UNITY_COLORSPACE_GAMMA) && !SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
        col = LINEAR_2_OUTPUT(col);
    #endif

    return half3x3(col, sunColor, half3(y, 0.0, 0.0));
}



//// float ////
void SkyboxColor_float(in float3 vertexIn, in float3 skyTint, in float exposure, in float3 groundColorIn,
                    in float3 sunDirection, in float3 sunColorIn, in float atmosphereThickness, in float sunSize,
                    in float sunCoverage, out float3 skyColor, out float3 sunColorOut, out float yValue)
{
    float3x3 result = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    skyColor = result[0];
    sunColorOut = result[1];
    yValue = result[2].x;
}



//// half ////
void SkyboxColor_half(in half3 vertexIn, in half3 skyTint, in half exposure, in half3 groundColorIn,
                    in half3 sunDirection, in half3 sunColorIn, in half atmosphereThickness, in half sunSize,
                    in half sunCoverage, out half3 skyColor, out half3 sunColorOut, out half yValue)
{
    half3x3 result = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    skyColor = result[0];
    sunColorOut = result[1];
    yValue = result[2].x;
}