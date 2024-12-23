#ifndef ProcedualSkybox
#define ProcedualSkybox
/*
Copyright (c) 2016 Unity Technologies

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#define unity_ColorSpaceDouble half4(4.59479380, 4.59479380, 4.59479380, 2.0)

#if defined(UNITY_COLORSPACE_GAMMA)
#define GAMMA 2
#define COLOR_2_GAMMA(color) color
#define COLOR_2_LINEAR(color) color*color
#define LINEAR_2_OUTPUT(color) sqrt(color)
#else
#define GAMMA 2.2
// HACK: to get gfx-tests in Gamma mode to agree until UNITY_ACTIVE_COLORSPACE_IS_GAMMA is working properly
#define COLOR_2_GAMMA(color) ((unity_ColorSpaceDouble.r>2.0) ? pow(color,1.0/GAMMA) : color)
#define COLOR_2_LINEAR(color) color
#define LINEAR_2_LINEAR(color) color
#endif

// RGB wavelengths
// .35 (.62=158), .43 (.68=174), .525 (.75=190)
static const float3 kDefaultScatteringWavelength = half3(.65, .57, .475);
static const float3 kVariableRangeForScatteringWavelength = float3(.15, .15, .15);
//static const float3 kVariableRangeForScatteringWavelength = float3(.1, .1, .1);

#define OUTER_RADIUS 1.025
static const float kOuterRadius = OUTER_RADIUS;
static const float kOuterRadius2 = OUTER_RADIUS*OUTER_RADIUS;
static const float kInnerRadius = 1.0;
static const float kInnerRadius2 = 1.0;
static const float kCameraHeight = 0.0001;


#define kMIE 0.0010             // Mie constant
#define kSUN_BRIGHTNESS 20.0    // Sun brightness
#define kMAX_SCATTER 50.0 // Maximum scattering value, to prevent math overflows on Adrenos
static const half kHDSundiskIntensityFactor = 15.0;
static const half kSunScale = 400.0 * kSUN_BRIGHTNESS;
static const float kKmESun = kMIE * kSUN_BRIGHTNESS;
static const float kKm4PI = kMIE * 4.0 * 3.14159265;
static const float kScale = 1.0 / (OUTER_RADIUS - 1.0);
static const float kScaleDepth = 0.25;
static const float kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
static const float kSamples = 2.0; // THIS IS UNROLLED MANUALLY, DON'T TOUCH

#define MIE_G (-0.990)
#define MIE_G2 0.9801

#define SKY_GROUND_THRESHOLD 0.02


#ifndef SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
    #if defined(SHADER_API_MOBILE)
        #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 1
    #else
        #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 0
    #endif
#endif

half unlerp(half a, half b, half t)
{
    return (t - a)/(b - a);
}


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
    //temp = pow(temp, .454545);
    return temp;
}

// Calculates the sun shape
half calcSunAttenuation(half3 lightPos, half3 ray, half coverage, half size)
{
    half focusedEyeCos = pow(saturate(dot(lightPos, ray)), coverage);
    return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos, size);
}

half2x3 CalculateSkybox(half3 vertex, half3 direction, half atmosphereThickness, half3 skyColor,
                            half3 groundColor, half3 sunColor, half exposure, half size, half coverage)
{
    half3 eyeRay = normalize(mul((half3x3)unity_ObjectToWorld, vertex.xyz));
    half3 kSkyTintInGammaSpace = COLOR_2_GAMMA(skyColor); // convert tint from Linear back to Gamma
    half multiplier = lerp(1, 0, saturate(abs(direction.y) * 2));
    half3 kScatteringWavelength = lerp (
        kDefaultScatteringWavelength - kVariableRangeForScatteringWavelength * multiplier,
        kDefaultScatteringWavelength + kVariableRangeForScatteringWavelength * multiplier,
        half3(1,1,1) - kSkyTintInGammaSpace); // using Tint in sRGB gamma allows for more visually linear interpolation and to keep (.5) at (128, gray in sRGB) point
    half3 kInvWavelength = 1.0 / pow(kScatteringWavelength, 4);

    half kRAYLEIGH = lerp(0.0, 0.0025, pow(atmosphereThickness * clamp(multiplier * 1.75, 1, 1.75), 1.75));
    half kKrESun = kRAYLEIGH * kSUN_BRIGHTNESS;
    half kKr4PI = kRAYLEIGH * 4.0 * 3.14159265;

    half3 cameraPos = half3(0,kInnerRadius + kCameraHeight,0);    // The camera's current position

    // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)

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
        sunColor *= calcSunAttenuation(direction.xyz, -ray, coverage, size);
    }
    else
    {
        sunColor = half3(0.0, 0.0, 0.0);
    }

    #if defined(UNITY_COLORSPACE_GAMMA) && !SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
        col = LINEAR_2_OUTPUT(col);
    #endif

    return half2x3(col, sunColor);
}




//// float ////
void SkyboxColor_float(in float3 vertexIn, in float3 skyTint, in float exposure, in float3 groundColorIn,
                    in float3 sunDirection, in float3 sunColorIn, in float atmosphereThickness, in float sunSize,
                    in float sunCoverage, in float zenithBlend, in float nadirBlend, 
                    in float3 groundColor, out float3 skyColor, out float3 sunColorOut, out float3 groundColorOut)
{
    float2x3 result = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    float a = clamp(vertexIn.y, 0.0, 1.0);
    float b = -clamp(vertexIn.y, -1.0, 0.0);
    a = pow(a, zenithBlend);
    b = pow(b, nadirBlend);
    skyColor = result[0] * a;
    groundColorOut = groundColor * b * skyColor;
    sunColorOut = result[1];
}



//// half ////
void SkyboxColor_half(in half3 vertexIn, in half3 skyTint, in half exposure, in half3 groundColorIn,
                    in half3 sunDirection, in half3 sunColorIn, in half atmosphereThickness, in half sunSize,
                    in half sunCoverage, in half zenithBlend, in half nadirBlend, 
                    in half3 groundColor, out half3 skyColor, out half3 sunColorOut, out half3 groundColorOut)
{
    half2x3 result = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    half a = clamp(vertexIn.y, 0.0, 1.0);
    half b = -clamp(vertexIn.y, -1.0, 0.0);
    a = pow(a, zenithBlend);
    b = pow(b, nadirBlend);
    skyColor = result[0] * a;
    groundColorOut = groundColor * b * skyColor;
    sunColorOut = result[1];
}



/*
Copyright (c) 2024 Cenk Bilgin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

//Fog
half4 GetFogDensity(half3 position, half offset, half power, half blend)
{
    return saturate(exp2(-((1.0 - power) * (position.y - offset)) / max(blend, 0)));
}

void FogDensity_half(half3 position, half offset, half power, half blend, out half result)
{
    result = GetFogDensity(position, offset, power, blend);
}

void FogDensity_float(half3 position, float offset, float power, float blend, out float result)
{
    result = GetFogDensity(position, offset, power, blend);
}



// Clouds
half2 SphereIntersect(half sphereRadius , half cosChi , half radialDistance , half rcpRadialDistance)
{
    half d = Sq(sphereRadius * rcpRadialDistance) - saturate(1 - cosChi * cosChi);
    return (d < 0) ? d : (radialDistance * half2(-cosChi - sqrt(d), -cosChi + sqrt(d)));
}

half2 SphereIntersect(half sphereRadius , half cosChi , half radialDistance)
{
    return SphereIntersect(sphereRadius, cosChi, radialDistance, rcp(radialDistance));
}

half3 GetCloudVolumeIntersection(int index, half3 dir)
{
    const half earthRadius = 6378100.0;
    return dir * -SphereIntersect(2000.0 + earthRadius, -dir.y, earthRadius).x;
}

half3 DegToOrientation(half deg)
{
    half rad = 2 * PI * deg / 360.0;
    return half3(cos(rad), sin(rad), 0.0);
}

half3 RotateAroundYInDegrees (half3 V, half degrees)
{
    half alpha = degrees * PI / 180.0;
    half sina, cosa;
    sincos(alpha, sina, cosa);
    half2x2 m = half2x2(cosa, -sina, sina, cosa);
    return half3(mul(m, V.xz), V.y).xzy;
}

half2 GetLatLongCoords(half3 dir , half upperHemisphereOnly, half yRotation)
{
    dir = RotateAroundYInDegrees(dir, yRotation);
    const half2 invAtan = half2( 0.1591 , 0.3183 );
    half fastAtan2 = FastAtan2( dir.x , dir.z );
    half2 uv = half2 (fastAtan2 , FastASin( dir.y ) ) * invAtan + 0.5;
    uv.y = upperHemisphereOnly ? uv.y * 2.0 - 1.0 : uv.y;
    return uv;
}

half PhaseHG(half g, half cosTheta)
{
    half g2 = g * g;
    half  nom = 1.0 - g2;
    half  denom = 4.0 * PI * pow(1.0 + g2 - 2.0 * g * (cosTheta), 1.5);
    return nom / denom;
}


half3 CalculateCloudSterngth(half4 color, half4 sterngth)
{
    color.r = color.r * sterngth.r;
    color.g = color.g * sterngth.g;
    color.b = color.b * sterngth.b;
    color.a = color.a * sterngth.a;
    half3 result = half3(color.r, color.r, color.r);
    result += half3(color.g, color.g, color.g);
    result += half3(color.b, color.b, color.b);
    result += half3(color.a, color.a, color.a);
    return result;
}



half4 CalculateClouds(Texture2D cloudMap, SamplerState ss, half3 positionWS, half3 worldCameraPos, half yRotation, half direction, half speed, half altitude, half4 strength, half3 skyColor, half density)
{
#if SHADERGRAPH_PREVIEW
    half3 lightDir = half3(0.5, 0.5, 0);
    half3 lightCol = 1;
#else
    Light mainLight = GetMainLight();
    half3 lightDir = normalize(mainLight.direction);
    half3 lightCol = mainLight.color;
#endif

    half3 view = normalize(worldCameraPos.xyz - positionWS.xyz);
    half3 panoPosition = GetCloudVolumeIntersection(0, -view);
    half scrollDist = 2 * altitude;
    half2 panoAlpha = frac(speed * _Time.y * 10 / scrollDist + half2(0.0, 0.5)) - 0.5;
    half3 scrollDirection = DegToOrientation(direction);
    half3 delta = half3(scrollDirection.x, 0.0, scrollDirection.y);
    half3 dir = normalize(panoPosition + panoAlpha.x * delta * scrollDist);
    half2 uvx = GetLatLongCoords(dir, 1.0, yRotation);
    dir = normalize(panoPosition + panoAlpha.y * delta * scrollDist);
    half2 uvy = GetLatLongCoords(dir, 1.0, yRotation);

    half4 colorX = SAMPLE_TEXTURE2D(cloudMap, ss, uvx);
    half4 colorY = SAMPLE_TEXTURE2D(cloudMap, ss, uvy);

    half3 viewDir = normalize(worldCameraPos.xyz - positionWS.xyz);
    lightDir = RotateAroundYInDegrees(lightDir, yRotation);

    half hgPhase = PhaseHG(0.8, dot(lightDir, viewDir));
    half3 color = lerp(CalculateCloudSterngth(colorX, strength), CalculateCloudSterngth(colorY, strength), abs(2.0 * panoAlpha.x));
    half3 shade = pow(-0.5 * color, 2);

    half3 weights = lightDir > 0 ? color : shade;
    half3 sqrDir = lightDir * lightDir;
    half transmission = dot(sqrDir, weights);

    half3 directDiffuse = exp(-1.0 * (1 - transmission) * density) * lightCol;
    half3 rimEnhance = min(1, pow(transmission, 6)) * hgPhase * lightCol * 10;
    directDiffuse += rimEnhance;
    directDiffuse.rgb = saturate(lerp(directDiffuse.rgb * 0.1, directDiffuse.rgb, saturate(length(skyColor))));

    half opacity = pow(color.y, 1.2);
    opacity = viewDir.y < 0 ? opacity : 0;
    opacity = saturate(opacity * normalize(positionWS).y);

    return half4(directDiffuse.rgb, opacity);
}


void Clouds_half(Texture2D cloudMap, SamplerState ss, half3 positionWS, half3 worldCameraPos, half yRotation, half direction, half speed, half altitude, half4 strength, half3 skyColor, half density, out half3 diffuse, out half opacity)
{
    half4 result = CalculateClouds(cloudMap, ss, positionWS, worldCameraPos, yRotation, direction, speed, altitude, strength, skyColor, density);
    diffuse = result.xyz;
    opacity = result.w;
}

void Clouds_float(Texture2D cloudMap, SamplerState ss, float3 positionWS, float3 worldCameraPos, float yRotation, float direction, float speed, float altitude, float4 strength, float3 skyColor, float density, out float3 diffuse, out float opacity)
{
    float4 result = CalculateClouds(cloudMap, ss, positionWS, worldCameraPos, yRotation, direction, speed, altitude, strength, skyColor, density);
    diffuse = result.xyz;
    opacity = result.w;
}



// Stars
half3 Contrast(float3 In, float c)
{
    float midpoint = pow(0.5, 2.2);
    return (In - midpoint) * c + midpoint;
}

half3 GetStarColor(half3 skyColor, TextureCube cube, SamplerState ss, half4x4 starMatrix, half3 dir, half3 gradient, half3 spaceTint, half intensity, half contrast)
{
    starMatrix[2] *= -1;
    starMatrix[2].w *= -1;
    dir = mul(starMatrix, dir);
    return Contrast(spaceTint * lerp(intensity * 0.01 * gradient * SAMPLE_TEXTURECUBE_LOD(cube, ss, dir, 0), 0.0, saturate(3.0 * (skyColor.r + skyColor.g + skyColor.b))), contrast);
}

void StarColor_half(half3 skyColor, TextureCube cube, SamplerState ss, half4x4 starMatrix, half3 dir, half3 gradient, half3 spaceTint, half intensity, half contrast, out half3 result)
{
    result = GetStarColor(skyColor, cube, ss, starMatrix, dir, gradient, spaceTint, intensity, contrast);
}

void StarColor_float(float3 skyColor, TextureCube cube, SamplerState ss, float4x4 starMatrix, float3 dir, float3 gradient, float3 spaceTint, float intensity, float contrast, out float3 result)
{
    result = GetStarColor(skyColor, cube, ss, starMatrix, dir, gradient, spaceTint, intensity, contrast);
}




half4 CalculateMoon(half4x4 moonMatrix, half3 viewDir, half size, half4 color, Texture2D tex, SamplerState ss)
{
    moonMatrix[2] *= -1;
    moonMatrix[2].w *= -1;
    half3 dir = mul(moonMatrix, viewDir);
    half2 uv = half2(dir.x, dir.y) / size;
    half d = dot(uv, uv);
    if (d <= 1 && dir.z < 0)
    {
        uv *= -0.5h;
        uv += 0.5h;
        return SAMPLE_TEXTURE2D(tex, ss, uv) * color;
    }
    else
    {
        return 0;
    }
}

void Moon_half(half4x4 moonMatrix, half3 viewDir, half size, half4 color, Texture2D tex, SamplerState ss, out half3 moon, out half alpha)
{
    half4 output = CalculateMoon(moonMatrix, viewDir, size, color, tex, ss);
    moon = output.rgb;
    alpha = output.a;
}

void Moon_float(float4x4 moonMatrix, float3 viewDir, float size, float4 color, Texture2D tex, SamplerState ss, out float3 moon, out float alpha)
{
    float4 output = CalculateMoon(moonMatrix, viewDir, size, color, tex, ss);
    moon = output.rgb;
    alpha = output.a;
}
#endif