//Copyright (c) 2016 Unity Technologies

//Permission is hereby granted, free of charge, to any person obtaining a copy of
//this software and associated documentation files (the "Software"), to deal in
//the Software without restriction, including without limitation the rights to
//use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//of the Software, and to permit persons to whom the Software is furnished to do
//so, subject to the following conditions:

//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.

//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


// RGB wavelengths
// .35 (.62=158), .43 (.68=174), .525 (.75=190)
static const half3 kDefaultScatteringWavelength = half3(.65, .57, .475);
static const half3 kVariableRangeForScatteringWavelength = half3(.15, .15, .15);

#define OUTER_RADIUS 1.025
static const half kOuterRadius = OUTER_RADIUS;
static const half kOuterRadius2 = OUTER_RADIUS*OUTER_RADIUS;
static const half kInnerRadius = 1.0;
static const half kInnerRadius2 = 1.0;

static const half kCameraHeight = 0.0001;

#define kMIE 0.0010             // Mie constant
#define kSUN_BRIGHTNESS 20.0    // Sun brightness

#define kMAX_SCATTER 50.0 // Maximum scattering value, to prevent math overflows on Adrenos

static const half kHDSundiskIntensityFactor = 15.0;
static const half kSimpleSundiskIntensityFactor = 27.0;

static const half kSunScale = 400.0 * kSUN_BRIGHTNESS;
static const half kKmESun = kMIE * kSUN_BRIGHTNESS;
static const half kKm4PI = kMIE * 4.0 * 3.14159265;
static const half kScale = 1.0 / (OUTER_RADIUS - 1.0);
static const half kScaleDepth = 0.25;
static const half kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
static const half kSamples = 2.0; // THIS IS UNROLLED MANUALLY, DON'T TOUCH

#define MIE_G (-0.990)
#define MIE_G2 0.9801
#define SKYBOX_PI 3.14159265

#define SKY_GROUND_THRESHOLD 0.02

half scale(float inCos)
{
    half x = 1.0 - inCos;
    return 0.25 * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
}

half getRayleighPhase(half eyeCos2)
{
    return 0.75 + 0.75 * eyeCos2;
}

half getRayleighPhase(half3 light, half3 ray)
{
    half eyeCos = dot(light, ray);
    return getRayleighPhase(eyeCos * eyeCos);
}

half3 RotateAroundYInDegrees (half3 vertex, half degrees)
{
    half alpha = degrees * SKYBOX_PI / 180.0;
    half sina, cosa;
    sincos(alpha, sina, cosa);
    half2x2 m = half2x2(cosa, -sina, sina, cosa);
    return half3(mul(m, vertex.xz), vertex.y).xzy;
}

// Calculates the Mie phase function
half getMiePhase(half eyeCos, half eyeCos2, half size)
{
    half temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;
    temp = pow(temp, pow(size,0.65) * 10);
    temp = max(temp,1.0e-4); // prevent division by zero, esp. in half precision
    temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
    return temp;
}

// Calculates the sun shape
half calcSunAttenuation(half3 lightPos, half3 ray, half size, half sizeCoverage)
{
    half focusedEyeCos = pow(saturate(dot(lightPos, ray)), sizeCoverage);
    return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos, size);
}


half2x3 CalculateSkyboxVert(half3 eyeRay, half3 direction, half rayLength, half3 skyTint)
{
    half3 kScatteringWavelength = lerp (
    kDefaultScatteringWavelength - kVariableRangeForScatteringWavelength,
    kDefaultScatteringWavelength + kVariableRangeForScatteringWavelength,
    half3(1, 1, 1) - skyTint); // using Tint in sRGB gamma allows for more visually linear interpolation and to keep (.5) at (128, gray in sRGB) point
    half kKrESun = rayLength * kSUN_BRIGHTNESS;
    half kKr4PI = rayLength * 4.0 * 3.14159265;
    half3 kInvWavelength = 1.0 / pow(kScatteringWavelength, 4);
    half3 cameraPos = half3(0,kInnerRadius + kCameraHeight,0);    // The camera's current position
    half far = 0.0;
    half3 cIn, cOut;

    if (eyeRay.y >= -0.1)
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
        //              for(int i=0; i<int(kSamples); i++)
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
        half cameraAngle = dot(-eyeRay, pos);
        half lightAngle = dot(_SunDirection.xyz, pos);
        half cameraScale = scale(cameraAngle);
        half lightScale = scale(lightAngle);
        // half depth = exp((-kCameraHeight) * (1.0/kScaleDepth));
        // half cameraOffset = depth * cameraScale;
        half cameraOffset = exp((-kCameraHeight) * (1.0/kScaleDepth)) * cameraScale;
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
            float height = length(samplePoint);
            float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            float scatter = depth*temp - cameraOffset;
            attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));
            frontColor += attenuate * (depth * scaledLength);
            samplePoint += sampleRay;
        }

        cIn = frontColor * (kInvWavelength * kKrESun + kKmESun);
        cOut = clamp(attenuate, 0.0, 1.0);
    }
    return half2x3(cIn, cOut);
}






//// float ////
void SkyboxVert_float(in half3 vertexIn, in half3 skyTint, in half exposure,
                    in half3 groundColorIn, in half3 sunDirection, in half3 sunColorIn, in half atmosphereThickness,
                    out half3 vertexOut, out half3 groundColorOut, out half3 skyColor, out half3 sunColorOut)
{
    half rayLength = lerp(0.0, 0.0025, pow(atmosphereThickness, 2.5));

    // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
    half3 eyeRay = normalize(mul((half3x3)unity_ObjectToWorld, vertexIn.xyz));

    vertexOut = -eyeRay;

    // if we want to calculate color in vprog:
    // 1. in case of linear: multiply by _Exposure in here (even in case of lerp it will be common multiplier, so we can skip mul in fshader)
    // 2. in case of gamma and SKYBOX_COLOR_IN_TARGET_COLOR_SPACE: do sqrt right away instead of doing that in fshader

    half2x3 color = CalculateSkyboxVert(eyeRay, sunDirection, rayLength, _SkyTint);
    
    groundColorOut = exposure * (color[0] + groundColorIn * color[1]);
    skyColor = exposure * (color[0] * getRayleighPhase(sunDirection.xyz, -eyeRay));
    half lightColorIntensity = clamp(length(sunColorIn.xyz), 0.25, 1);
    sunColorOut = kHDSundiskIntensityFactor * saturate(color[1]) * sunColorIn.xyz / lightColorIntensity;
}


void GetRay_float(in half3 vertex, out half3 ray, out half yValue)
{
    ray = normalize(vertex.xyz);
    yValue = ray.y / SKY_GROUND_THRESHOLD;
}


void GetSkyColor_float(in half yValue, in half3 groundColor, in half3 skyColor, out half3 col)
{
    col = lerp(skyColor, groundColor, saturate(yValue));
}


void GetSunColor_float(in half3 ray, in half yValue, in half3 direction, in half size, in half coverage, in half3 sunColor, out half3 result)
{
    if (yValue < -0.1)
    {
        result = sunColor * calcSunAttenuation(direction.xyz, -ray, size, coverage);
    }
    else result = half3(0.0, 0.0, 0.0);
}









//// half ////
void SkyboxVert_half(in half3 vertexIn, in half3 skyTint, in half exposure,
                    in half3 groundColorIn, in half3 sunDirection, in half3 sunColorIn, in half atmosphereThickness,
                    out half3 vertexOut, out half3 groundColorOut, out half3 skyColor, out half3 sunColorOut)
{
    half rayLength = lerp(0.0, 0.0025, pow(atmosphereThickness, 2.5));

    // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
    half3 eyeRay = normalize(mul((half3x3)unity_ObjectToWorld, vertexIn.xyz));

    vertexOut = -eyeRay;

    // if we want to calculate color in vprog:
    // 1. in case of linear: multiply by _Exposure in here (even in case of lerp it will be common multiplier, so we can skip mul in fshader)
    // 2. in case of gamma and SKYBOX_COLOR_IN_TARGET_COLOR_SPACE: do sqrt right away instead of doing that in fshader

    half2x3 color = CalculateSkyboxVert(eyeRay, sunDirection, rayLength, _SkyTint);
    
    groundColorOut = exposure * (color[0] + groundColorIn * color[1]);
    skyColor = exposure * (color[0] * getRayleighPhase(sunDirection.xyz, -eyeRay));
    half lightColorIntensity = clamp(length(sunColorIn.xyz), 0.25, 1);
    sunColorOut = kHDSundiskIntensityFactor * saturate(color[1]) * sunColorIn.xyz / lightColorIntensity;
}


void GetRay_half(in half3 vertex, out half3 ray, out half yValue)
{
    ray = normalize(vertex.xyz);
    yValue = ray.y / SKY_GROUND_THRESHOLD;
}


void GetSkyColor_half(in half yValue, in half3 groundColor, in half3 skyColor, out half3 col)
{
    col = lerp(skyColor, groundColor, saturate(yValue));
}


void GetSunColor_half(in half3 ray, in half yValue, in half3 direction, in half size, in half coverage, in half3 sunColor, out half3 result)
{
    if (yValue < -0.1)
    {
        result = sunColor * calcSunAttenuation(direction.xyz, -ray, size, coverage);
    }
    else result = half3(0.0, 0.0, 0.0);
}