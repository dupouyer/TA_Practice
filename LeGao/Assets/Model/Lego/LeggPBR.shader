Shader "PBR/LegoPBR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _SmoothnessTex("Smoothness", 2D) = "white" {}
        
        _SpecularRate("Specular Rate", Range(1,5)) = 1
        _NoiseTex("NoiseTex", 2D) = "dark" {}
        _SpecularMap("SpecularMap", 2D) = "black" {}
        
        _FrontSssDistortion("_FrontSssDistortion", Range(0,1)) = 0.5
        _BackSssDistortion("_BackSssDistortion", Range(0,1)) = 0.5
        _FrontSssIntensity("_FrontSssIntensity", Range(0,1)) = 0.2
        _BackSssIntensity("_FrontSssIntensity", Range(0,1)) = 0.2
        _InteriorColorPower("InteriorColorPower", Range(0, 5)) = 2
        
        _UnLitRate("UnLitRate", Range(0,1)) = 0.5
        _AmbientLight("Ambient Light", Color) = (0.5,0.5,0.5,0.5)
        
        _FresnelPower("Fresnel Power", Range(0.0, 5)) = 1.0
        _FresnelIntensity("Fresnel Intensity", Range(0, 1)) = 0.2
        
        _RimColor("Rim Color", Color) = (0.5, 0.5, 0.5, 1)
        _RimIntensity("Rim Intensity", Range(0.0, 5)) = 1.0
        _RimLightSampler("Rim Mask", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float3 normalWS : TEXCOORD1;
                float3 lightWS : TEXCOORD2;
                float3 viewWS : TEXCOORD3;
                float4 worldPos : TEXCOORD4;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _SmoothnessTex;
            sampler2D _SpecularMap;
            sampler2D _NoiseTex;
            float4 _NoiseTex_ST;
            sampler2D _RimLightSampler;

            float _UnLitRate;
            float4 _AmbientLight;

            float _SpecularRate;

            float _FrontSssDistortion;
            float _BackSssDistortion;
            float _FrontSssIntensity;
            float _BackSssIntensity;
            float _InteriorColorPower;

            float4 _RimColor;
            float _RimIntensity;

            float _FresnelPower;
            float _FresnelIntensity;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS = normalize(UnityObjectToWorldNormal(v.normal));
                o.lightWS = normalize(_WorldSpaceLightPos0);
                o.viewWS = normalize(_WorldSpaceCameraPos - o.worldPos);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed SubsurfaceScattering(fixed3 viewDir, fixed3 lightDir, fixed3 normalDir, float frontSubsurfaceDistortion, float backSubsurfaceDistortion, float frontSssIntensity )
            {
                float3 frontLitDir = normalDir * frontSubsurfaceDistortion - lightDir;
                float3 backLitDir = normalDir * backSubsurfaceDistortion + lightDir;

                float frontSSS = saturate(dot(viewDir, -frontLitDir));
                float backSSS = saturate(dot(viewDir, -backLitDir));

                float result = saturate(frontSSS * frontSssIntensity + backSSS);
                return result;
            }

            float4 frag (v2f i) : SV_Target
            {
                // sample the texture
                float4 col = tex2D(_MainTex, i.uv);
                
                float noise = tex2D(_NoiseTex, TRANSFORM_TEX(i.uv, _NoiseTex));
                float smoothness = tex2D(_SmoothnessTex, i.uv);
                float specular_t = 1 - tex2D(_SpecularMap, i.uv).r;
                
                float4 interiorSpecular = float4(0.5,0.3,0,1);

                // common data
                float NdotL = dot(i.normalWS, i.lightWS);
                float NdotV = dot(i.normalWS, i.viewWS);
                float shadowAtten = SHADOW_ATTENUATION(i);

                float lightRate = saturate((_LightColor0.x + _LightColor0.y + _LightColor0.z) * 0.3334);
                float lightingValue = saturate(NdotL * shadowAtten) * lightRate;
                float4 lightCol = lerp(_LightColor0, float4(1,1,1,1), 0.6);

                // sss
                float sssValue =  SubsurfaceScattering(i.viewWS, i.lightWS, i.normalWS, _FrontSssDistortion, _BackSssDistortion, _FrontSssIntensity);
                float3 sssCol = lerp(interiorSpecular, _LightColor0, saturate(pow(sssValue,_InteriorColorPower))).rgb * sssValue;
                sssCol *= _BackSssIntensity;

                // Diffuse
                float4 unlitCol = col * interiorSpecular * _UnLitRate;
                float4 diffCol = lerp(unlitCol, col, lightingValue) * lightCol;

                // Specular
                float gloss = lerp(0.95, 0.3, specular_t);
                float specularPow = exp2((1 - gloss) * 5.0 + 1.0);
                float3 halfVector = normalize(i.lightWS + i.viewWS);
                
                float directSpecular = pow(max(0, dot(halfVector, i.normalWS)), specularPow) * specular_t;
                float specular = directSpecular * lerp(lightingValue, 1, 0.4) * _SpecularRate;
                float noiseSpecular = lerp(specular, lerp(1- pow(noise, specular), specular, specular), smoothness);
                float3 specularCol = noiseSpecular * _LightColor0.rgb;

                float falloffU = clamp(1.0 - abs(NdotV), 0.02, 0.98);
                float rimLightDot = saturate(0.5 * (dot(i.normalWS, i.lightWS) + 1.5));
                falloffU = saturate(rimLightDot * falloffU);
                falloffU = tex2D(_RimLightSampler, float2(falloffU, 0.25));
                float3 rimCol = falloffU * _RimColor * _RimIntensity * lerp(lightingValue, 1, 0.6);

                float fresnel = 1.0 - max(0, NdotV);
                float fresnelValue = lerp(fresnel ,0 , sssValue);

                float3 fresnelCol = saturate(lerp(interiorSpecular, lightCol, fresnelValue) * pow(fresnelValue, _FresnelPower) * _FresnelIntensity);

                float3 final = sssCol + diffCol.rgb + specularCol + fresnelCol + rimCol;
                
                UNITY_APPLY_FOG(i.fogCoord, finalCol);
                return float4(final.rgb, 1);
            }
            ENDCG
        }
    }
}
