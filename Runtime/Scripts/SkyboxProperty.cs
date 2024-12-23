using UnityEngine;

namespace AdvancedProceduralSkybox
{
    public readonly struct SkyboxProperty
    {
        private static readonly int MoonMatrix = Shader.PropertyToID("_MoonMatrix");
        private static readonly int SunDirection = Shader.PropertyToID("_SunDirection");
        private static readonly int StarMatrix = Shader.PropertyToID("_StarMatrix");
        private static readonly int FogDensity = Shader.PropertyToID("_FogDensity");
        private static readonly int FogPower = Shader.PropertyToID("_FogPower");
        private static readonly int FogOffset = Shader.PropertyToID("_FogOffset");
        private static readonly int CloudSterngth = Shader.PropertyToID("_CloudStrength");
        private static readonly int FogColor = Shader.PropertyToID("_FogColor");
        private static readonly int SunRate = Shader.PropertyToID("_SunRate");


        public static void SetStarMatrix(Material skybox, Transform transform)
        {
            SetStarMatrix(skybox, transform.worldToLocalMatrix);
        }

        public static void SetStarMatrix(Material skybox, Matrix4x4 matrix)
        {
            skybox.SetMatrix(StarMatrix, matrix);
        }

        public static void SetSunDirection(Material skybox, Vector3 direction)
        {
            skybox.SetVector(SunDirection, direction);
        }

        public static void SetMoonMatrix(Material skybox, Transform transform)
        {
            SetMoonMatrix(skybox, transform.worldToLocalMatrix);
        }

        public static void SetMoonMatrix(Material skybox, Matrix4x4 matrix)
        {
            skybox.SetMatrix(MoonMatrix, matrix);
        }

        public static void SetFogColor(Material skybox, Color color)
        {
            skybox.SetColor(FogColor, color);
        }

        public static void SetFogPower(Material skybox, float power)
        {
            skybox.SetFloat(FogPower, power);
        }

        public static void SetFogOffset(Material skybox, float offset)
        {
            skybox.SetFloat(FogOffset, offset);
        }

        public static void SetSunRate(Material skybox, float rate)
        {
            skybox.SetFloat(SunRate, rate);
        }

        public static void SetCloudSterngth(Material skybox, Vector4 strength)
        {
            skybox.SetVector(CloudSterngth, strength);
        }
    }
}
