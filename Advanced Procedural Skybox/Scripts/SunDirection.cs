using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SunDirection : MonoBehaviour
{
    public Material skybox;
    // Start is called before the first frame update
    void Start()
    {
        if (skybox != null)
        {
            RenderSettings.skybox = skybox;
        }
    }

    // Update is called once per frame
    void Update()
    {
        if (skybox != null)
        {
            skybox.SetVector("_SunDirection", -transform.forward);
        }
    }
}
