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
static const float3 kDefaultScatteringWavelength = float3(.65, .57, .475);
static const float3 kVariableRangeForScatteringWavelength = float3(.15, .15, .15);

#define OUTER_RADIUS 1.025
static const float kOuterRadius = OUTER_RADIUS;
static const float kOuterRadius2 = OUTER_RADIUS*OUTER_RADIUS;
static const float kInnerRadius = 1.0;
static const float kInnerRadius2 = 1.0;

static const float kCameraHeight = 0.0001;

#define kMIE 0.0010             // Mie constant
#define kSUN_BRIGHTNESS 20.0    // Sun brightness

#define kMAX_SCATTER 50.0 // Maximum scattering value, to prevent math overflows on Adrenos

static const float kHDSundiskIntensityFactor = 15.0;
static const float kSimpleSundiskIntensityFactor = 27.0;

static const float kSunScale = 400.0 * kSUN_BRIGHTNESS;
static const float kKmESun = kMIE * kSUN_BRIGHTNESS;
static const float kKm4PI = kMIE * 4.0 * 3.14159265;
static const float kScale = 1.0 / (OUTER_RADIUS - 1.0);
static const float kScaleDepth = 0.25;
static const float kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
static const float kSamples = 2.0; // THIS IS UNROLLED MANUALLY, DON'T TOUCH

#define MIE_G (-0.990)
#define MIE_G2 0.9801
#define SKYBOX_PI 3.14159265
#define HORIZON (-0.1)

#define SKY_GROUND_THRESHOLD 0.05

float scale(float inCos)
{
    float x = 1.0 - inCos;
    return 0.25 * exp(-0.00287 + x * (0.459 + x*(3.83 + x * (-6.80 + x * 5.25))));
}

float getRayleighPhase(float eyeCos2)
{
    return 0.75 + 0.75 * eyeCos2;
}

float getRayleighPhase(float3 light, float3 ray)
{
    float eyeCos = dot(light, ray);
    return getRayleighPhase(eyeCos * eyeCos);
}

float3 RotateAroundYInDegrees (float3 vertex, float degrees)
{
    float alpha = degrees * SKYBOX_PI / 180.0;
    float sina, cosa;
    sincos(alpha, sina, cosa);
    float2x2 m = float2x2(cosa, -sina, sina, cosa);
    return float3(mul(m, vertex.xz), vertex.y).xzy;
}

// Calculates the Mie phase function
float getMiePhase(float eyeCos, float eyeCos2, float size)
{
    float temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;
    temp = pow(temp, pow(size,0.65) * 10);
    temp = max(temp,1.0e-4); // prevent division by zero, esp. in float precision
    temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
    return temp;
}

// Calculates the sun shape
float calcSunAttenuation(float3 lightPos, float3 ray, float size, float sizeCoverage)
{
    float focusedEyeCos = pow(saturate(dot(lightPos, ray)), sizeCoverage);
    return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos, size);
}


float2x4 CalculateSkybox(float3 vertex, float3 direction, float atmosphereThickness, float3 skyColor,
                            float3 groundColor, float3 sunColor, float exposure, float size, float coverage)
{
    // Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
    float3 eyeRay = normalize((mul((float3x3)unity_ObjectToWorld, vertex.xyz)));
    float rayLength = lerp(0.0, 0.0025, pow(atmosphereThickness, 2.5));
    float3 kScatteringWavelength = lerp (
    kDefaultScatteringWavelength - kVariableRangeForScatteringWavelength,
    kDefaultScatteringWavelength + kVariableRangeForScatteringWavelength,
    float3(1, 1, 1) - skyColor); // using Tint in sRGB gamma allows for more visually linear interpolation and to keep (.5) at (128, gray in sRGB) point
    float kKrESun = rayLength * kSUN_BRIGHTNESS;
    float kKr4PI = rayLength * 4.0 * 3.14159265;
    float3 kInvWavelength = 1.0 / pow(kScatteringWavelength, 4);
    float3 cameraPos = float3(0,kInnerRadius + kCameraHeight,0);    // The camera's current position
    float far = 0.0;
    float3 cIn, cOut;

    if (eyeRay.y >= HORIZON)
    {
        // Sky
        // Calculate the length of the "atmosphere"
        far = sqrt(kOuterRadius2 + kInnerRadius2 * eyeRay.y * eyeRay.y - kInnerRadius2) - kInnerRadius * eyeRay.y;

        float3 pos = cameraPos + far * eyeRay;

        // Calculate the ray's starting position, then calculate its scattering offset
        float height = kInnerRadius + kCameraHeight;
        float depth = exp(kScaleOverScaleDepth * (-kCameraHeight));
        float startAngle = dot(eyeRay, cameraPos) / height;
        float startOffset = depth*scale(startAngle);

        // Initialize the scattering loop variables
        float sampleLength = far / kSamples;
        float scaledLength = sampleLength * kScale;
        float3 sampleRay = eyeRay * sampleLength;
        float3 samplePoint = cameraPos + sampleRay * 0.5;

        // Now loop through the sample rays
        float3 frontColor = float3(0.0, 0.0, 0.0);
        // Weird workaround: WP8 and desktop FL_9_3 do not like the for loop here
        // (but an almost identical loop is perfectly fine in the ground calculations below)
        // Just unrolling this manually seems to make everything fine again.
        //              for(int i=0; i<int(kSamples); i++)
        {
            float height = length(samplePoint);
            float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            float lightAngle = dot(direction.xyz, samplePoint) / height;
            float cameraAngle = dot(eyeRay, samplePoint) / height;
            float scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
            float3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

            frontColor += attenuate * (depth * scaledLength);
            samplePoint += sampleRay;
        }
        {
            float height = length(samplePoint);
            float depth = exp(kScaleOverScaleDepth * (kInnerRadius - height));
            float lightAngle = dot(direction.xyz, samplePoint) / height;
            float cameraAngle = dot(eyeRay, samplePoint) / height;
            float scatter = (startOffset + depth*(scale(lightAngle) - scale(cameraAngle)));
            float3 attenuate = exp(-clamp(scatter, 0.0, kMAX_SCATTER) * (kInvWavelength * kKr4PI + kKm4PI));

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

        float3 pos = cameraPos + far * eyeRay;

        // Calculate the ray's starting position, then calculate its scattering offset
        float cameraAngle = dot(-eyeRay, pos);
        float lightAngle = dot(_SunDirection.xyz, pos);
        float cameraScale = scale(cameraAngle);
        float lightScale = scale(lightAngle);
        // float depth = exp((-kCameraHeight) * (1.0/kScaleDepth));
        // float cameraOffset = depth * cameraScale;
        float cameraOffset = exp((-kCameraHeight) * (1.0/kScaleDepth)) * cameraScale;
        float temp = (lightScale + cameraScale);

        // Initialize the scattering loop variables
        float sampleLength = far / kSamples;
        float scaledLength = sampleLength * kScale;
        float3 sampleRay = eyeRay * sampleLength;
        float3 samplePoint = cameraPos + sampleRay * 0.5;

        // Now loop through the sample rays
        float3 frontColor = float3(0.0, 0.0, 0.0);
        float3 attenuate;
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

    // if we want to calculate color in vprog:
    // 1. in case of linear: multiply by _Exposure in here (even in case of lerp it will be common multiplier, so we can skip mul in fshader)
    // 2. in case of gamma and SKYBOX_COLOR_IN_TARGET_COLOR_SPACE: do sqrt right away instead of doing that in fshader

    float3 ray = normalize(-eyeRay);
    float y = (ray.y / SKY_GROUND_THRESHOLD) -1;

    groundColor = exposure * (cIn + groundColor * cOut);
    skyColor = exposure * (cIn * getRayleighPhase(direction.xyz, -eyeRay));
    float lightColorIntensity = clamp(length(sunColor.xyz), 0.25, 1);
    sunColor = kHDSundiskIntensityFactor * saturate(cOut) * sunColor.xyz / lightColorIntensity;

    float4 result0, result1;
    result0 = float4(lerp(skyColor, groundColor, saturate(y)), 1.0);

    if (y < HORIZON)
    {
        result1 = float4(sunColor * calcSunAttenuation(direction.xyz, -ray, size, coverage), y);
    }
    else
    {
        result1 = float4(0, 0, 0, y);
    }

    return float2x4(result0, result1);
}






//// half ////
void SkyboxVert_half(in float3 vertexIn, in float3 skyTint, in float exposure, in float3 groundColorIn,
                    in float3 sunDirection, in float3 sunColorIn, in float atmosphereThickness, in float sunSize,
                    in float sunCoverage, out float3 skyColor, out float3 sunColorOut, out float yValue)
{
    float2x4 color = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    skyColor = color[0].xyz;
    sunColorOut = color[1].xyz;
    yValue = color[1].w;
}





//// float ////
void SkyboxVert_float(in float3 vertexIn, in float3 skyTint, in float exposure, in float3 groundColorIn,
                    in float3 sunDirection, in float3 sunColorIn, in float atmosphereThickness, in float sunSize,
                    in float sunCoverage, out float3 skyColor, out float3 sunColorOut, out float yValue)
{
    float2x4 color = CalculateSkybox(vertexIn, sunDirection, atmosphereThickness, skyTint,
                                        groundColorIn, sunColorIn, exposure, sunSize, sunCoverage);
    skyColor = color[0].xyz;
    sunColorOut = color[1].xyz;
    yValue = color[1].w;
}

