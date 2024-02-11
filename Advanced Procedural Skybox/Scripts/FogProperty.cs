using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class FogProperty : MonoBehaviour
{
    public Material skybox;
    public float fogDensity = 0.001f;

    // Update is called once per frame
    void Update()
    {
        if (skybox != null)
        {
            skybox.SetFloat("_FogDensity", fogDensity);
        }
    }
}
