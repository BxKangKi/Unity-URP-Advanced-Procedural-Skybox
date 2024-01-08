#ifdef UNITY_COLORSPACE_GAMMA
#define GAMMA 2
#define COLOR_2_GAMMA(color) color
#define COLOR_2_LINEAR(color) color*color
#define LINEAR_2_OUTPUT(color) sqrt(color)
#define unity_ColorSpaceDouble half4(2.0, 2.0, 2.0, 2.0)
#else
#define GAMMA 2.2
// HACK: to get gfx-tests in Gamma mode to agree until UNITY_ACTIVE_COLORSPACE_IS_GAMMA is working properly
#define COLOR_2_GAMMA(color) ((unity_ColorSpaceDouble.r>2.0) ? pow(color,1.0/GAMMA) : color)
#define COLOR_2_LINEAR(color) color
#define LINEAR_2_LINEAR(color) color
#define unity_ColorSpaceDouble half4(4.59479380, 4.59479380, 4.59479380, 2.0)
#endif


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

#ifndef SKYBOX_COLOR_IN_TARGET_COLOR_SPACE
    #if defined(SHADER_API_MOBILE)
        #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 1
    #else
        #define SKYBOX_COLOR_IN_TARGET_COLOR_SPACE 0
    #endif
#endif