Shader "Fast Campus/Lit - Toon"
{
    HLSLINCLUDE
    #pragma multi_compile_fog
    #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
    #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION

    #include "Assets/Render/Bundle/ShaderLibrary/Lit.hlsl"

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS : NORMAL;
        float2 uv : TEXCOORD0;
        float4 color : COLOR;
    };

    struct Varyings
    {
        float4 position : SV_POSITION;
        float3 normalWs : NORMAL;
        float2 uv : TEXCOORD0;
        float3 positionWS : TEXCOORD2;
        float4 color : COLOR;
        float4 fogFactorAndGi : TEXCOORD3;
    };
    
    cbuffer UnityPerMaterial
    {
        float _Offset;
        float _OutlineWidth;
        half4 _OutlineColor;
        half3 _SpecColor;
        half3 _LitColorTint;
        half3 _ShadeColorTint;
        half _FresnelExp;
    }

    Texture2D<half4> _BaseColorTex;
    Texture2D<half4> _ShadeColorTex;
    Texture2D<half4> _OutlineColorTex;
    Texture2D<half> _RoughnessTex;
    Texture2D<half> _OcclusionTex;
    Texture2D<half> _MetallicTex;
    SamplerState sampler_BaseColorTex;
    SamplerState sampler_ShadeColorTex;
    SamplerState sampler_OutlineColorTex;
    SamplerState sampler_RoughnessTex;
    SamplerState sampler_OcclusionTex;
    SamplerState sampler_MetallicTex;

    float3 _LightDirection;
    float3 _LightPosition;

    float4 GetShadowPositionHClip(Attributes input)
    {
        float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
        const float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

        #if _CASTING_PUNCTUAL_LIGHT_SHADOW
        float3 lightDirectionWS = normalize(_LightPosition - positionWS);
        #else
        float3 lightDirectionWS = _LightDirection;
        #endif

        float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

        #if UNITY_REVERSED_Z
        positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
        #else
        positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
        #endif

        return positionCS;
    }
    ENDHLSL

    Properties
    {
        _Offset ("Radiance Offset", Range(-1.0, 1.0)) = 0.0
        _BaseColorTex ("Base Color", 2D) = "white" {}
        _ShadeColorTex ("Shade Color", 2D) = "black" {}
        _OutlineColorTex ("Outline Color", 2D) = "black" {}
        _RoughnessTex ("Roughness", 2D) = "white" {}
        _OcclusionTex ("Occlusion", 2D) = "white" {}
        _MetallicTex ("Metallic", 2D) = "black" {}

        [HDR] _LitColorTint ("Lit Color Tint", Color) = (1, 1, 1, 1)
        [HDR] _ShadeColorTint ("Lit Color Tint", Color) = (1, 1, 1, 1)
        [HDR] _SpecColor ("Specular Color", Color) = (0, 0, 0, 0)
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 0)
        
        _OutlineWidth ("Outline Width", Range(0.0, 0.1)) = 0.0
        _FresnelExp ("Fresnel Exponential", Range(0.1, 8.0)) = 0.0

        [Toggle] _ReceiveShadow ("Receive Shadow", Integer) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "Forward Lit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Cull Back
            ZTest LEqual
            ZWrite On

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            #pragma dynamic_branch_local_fragment _ReceiveShadow

            Varyings Vert(const Attributes input)
            {
                const VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                const VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                const float fogFactor = ComputeFogFactor(positionInputs.positionCS.z);
                const half3 gi = SampleSH(normalInputs.normalWS);

                Varyings output;
                output.position = positionInputs.positionCS;
                output.normalWs = normalInputs.normalWS;
                output.uv = input.uv;
                output.positionWS = positionInputs.positionWS.xyz;
                output.color = input.color;
                output.fogFactorAndGi = float4(fogFactor, gi.xyz);
                return output;
            }

            LitData InitializeLitData(const Varyings input)
            {
                const float2 uv = input.uv.xy;
        
                const half4 baseColor = _BaseColorTex.Sample(sampler_BaseColorTex, uv);
                const half4 shadeColor = _ShadeColorTex.Sample(sampler_ShadeColorTex, uv);
                const half roughness = _RoughnessTex.Sample(sampler_RoughnessTex, uv);
                const half occlusion = _OcclusionTex.Sample(sampler_OcclusionTex, uv);
                const half metallic = _MetallicTex.Sample(sampler_MetallicTex, uv);
        
                const half3 gi = input.fogFactorAndGi.yzw;
        
                LitData litData = GetDefaultLitData(input.positionWS);  
                litData.baseColor = baseColor.xyz * _LitColorTint.xyz;
                litData.shadeColor = shadeColor.xyz * _ShadeColorTint.xyz;
                litData.positionWS = input.positionWS;
                litData.specular = _SpecColor;
                litData.normal = normalize(input.normalWs.xyz);
                litData.radianceOffset = _Offset;
                litData.gi = gi;
                litData.roughness = roughness;
                litData.metallic = metallic;
                litData.occlusion = occlusion;
                litData.fresnelExp = _FresnelExp;
                litData.receiveShadow = _ReceiveShadow == 0;
                return litData;
            }

            half4 Frag(const Varyings input) : SV_TARGET
            {
                const LitData litData = InitializeLitData(input);
                const half fogFactor = input.fogFactorAndGi.x;
                half3 lit = Lit(litData);
                lit = MixFog(lit, fogFactor);
                return half4(lit.xyz, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags
            {
                "LightMode" = "Outline"
            }

            ZTest Less
            ZWrite On
            Cull Front

            HLSLPROGRAM
            #pragma vertex VertOutline
            #pragma fragment FragOutline

            Varyings VertOutline(const Attributes input)
            {
                const float3 normalWS = TransformObjectToWorldNormal(input.normalOS.xyz);
                const float3 positionWS = TransformObjectToWorld(input.positionOS.xyz) + normalWS * _OutlineWidth * input.color.x;
                const float4 positionCS = TransformWorldToHClip(positionWS);

                Varyings output = (Varyings)0;
                output.position = positionCS;
                output.uv = input.uv;
                return output;
            }

            half4 FragOutline(const Varyings input) : SV_TARGET
            {
                const float2 uv = input.uv;
                const half4 outlineColorTex = _OutlineColorTex.Sample(sampler_OutlineColorTex, uv);
                return half4(outlineColorTex.xyz * _OutlineColor.xyz, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            Cull Back
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex VertDepth
            #pragma fragment FragDepth

            Varyings VertDepth(const Attributes input)
            {
                const VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);

                Varyings output = (Varyings)0;
                output.position = posInputs.positionCS;
                return output;
            }

            half4 FragDepth(const Varyings input) : SV_TARGET { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            HLSLPROGRAM
            #pragma vertex VertShadow
            #pragma fragment FragShadow

            Varyings VertShadow(const Attributes input)
            {
                const float4 positionCS = GetShadowPositionHClip(input);
                Varyings output = (Varyings)0;
                output.position = positionCS;
                return output;
            }

            half4 FragShadow(const Varyings input) : SV_TARGET { return 0; }
            ENDHLSL
        }
    }
}
