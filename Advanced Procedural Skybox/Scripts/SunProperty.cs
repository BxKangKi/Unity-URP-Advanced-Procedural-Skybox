using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class SunProperty : MonoBehaviour
{
    public Material skybox;

    // Update is called once per frame
    void Update()
    {
        if (skybox != null) {
            skybox.SetVector("_SunDirection", -transform.forward);
        }
    }
}
