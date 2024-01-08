using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class MoonProperty : MonoBehaviour
{
    public Material skybox;

    // Update is called once per frame
    void Update()
    {
        if (skybox != null) {
            skybox.SetVector("_MoonForward", -transform.forward);
            skybox.SetVector("_MoonUp", transform.up);
            skybox.SetVector("_MoonRight", transform.right);
        }
    }
}
