#ifndef _INCLUDE_LIT
#define _INCLUDE_LIT

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct LitData
{
    half3 baseColor;
    half3 shadeColor;
    float4 shadowCoord;
    float3 positionWS;
    float3 normal;
    float3 view;
    half3 specular;
    half radianceOffset;
    half fresnelExp;
    half roughness;
    half metallic;
    half occlusion;
    half3 gi;

    bool receiveShadow;
};

struct Reflectance
{
    half fresnel;
    half radiance;
    half3 directDiffuse;
    half3 directSpecular;
    half3 indirectDiffuse;
    half3 indirectSpecular;
};

LitData GetDefaultLitData(const float3 positionWs)
{
    const float4 shadowCoord = TransformWorldToShadowCoord(positionWs);
    const half3 view = GetWorldSpaceViewDir(positionWs);
    
    LitData output;
    output.baseColor = half3(1.0h, 1.0h, 1.0h);
    output.shadeColor = half3(0.0h, 0.0h, 0.0h);
    output.shadowCoord = shadowCoord;
    output.positionWS = float3(0.0f, 0.0f, 0.0f);
    output.normal = float3(0.0f, 1.0f, 0.0f);
    output.view = view;
    output.specular = half3(1.0h, 1.0h, 1.0h);
    output.radianceOffset = 0.0h;
    output.fresnelExp = 2.0h;
    output.roughness = 1.0h;
    output.metallic = 0.0h;
    output.occlusion = 1.0h;
    output.gi = half3(0.0h, 0.0h, 0.0h);

    output.receiveShadow = true;
    return output;
}

Reflectance ToonDiffuseReflectance(const LitData litData, const Light light, Reflectance reflectance)
{
    const half radianceBase = dot(litData.normal, light.direction);
    reflectance.radiance = step(litData.radianceOffset, (radianceBase * 0.5h + 0.5h) * light.distanceAttenuation);

    if (litData.receiveShadow)
    {
        reflectance.radiance *= light.shadowAttenuation;
    }

    reflectance.directDiffuse = lerp(litData.shadeColor.xyz, litData.baseColor.xyz * light.color, reflectance.radiance);
    return reflectance;
}

Reflectance GetFresnel(const LitData litData, Reflectance reflectance)
{
    const half ndv = 1.0h - dot(litData.view, litData.normal);
    const half fresnel = step(0.1h, pow(max(ndv, 0.0h), exp2(litData.fresnelExp)));
    reflectance.fresnel = fresnel * reflectance.radiance;
    return reflectance;
}

Reflectance ToonSpecularReflectance(const LitData litData, const Light light, Reflectance reflectance)
{
    const half smoothness = 1.0h - litData.roughness;
    const half3 halfVector = normalize(litData.view + light.direction);
    const half ndh = max(dot(halfVector, litData.normal), 0.0h);
    const half blinnPhong = pow(ndh, smoothness * 10.0h + 1.0h) * smoothness;
    const half spec = 1.0h + max(max(litData.specular.x, litData.specular.y), litData.specular.z);
    const half blinnPhongStep = step(0.5h, spec * blinnPhong);
    reflectance.directSpecular = blinnPhongStep * litData.specular * reflectance.radiance;
    return reflectance;
}

Reflectance GetGi(const LitData litData, Reflectance reflectance)
{
    const half3 reflectVector = reflect(-litData.view, litData.normal);
    const half r = litData.roughness;
    const half r2 = r * r;
    const half3 reflection = GlossyEnvironmentReflection(reflectVector, litData.positionWS, r, litData.occlusion);

    reflectance.indirectDiffuse = litData.gi * reflectance.directDiffuse;

    const float surfaceReduction = 1.0f / (r2 + 1.0f);
    reflectance.indirectSpecular = reflection * half3(surfaceReduction * lerp(litData.specular, litData.metallic * 0.96h, reflectance.fresnel));
    return reflectance;
}

half3 Lit(const LitData litData)
{
    const Light lit = GetMainLight(litData.shadowCoord, litData.positionWS, half4(1, 1, 1, 1));

    Reflectance reflectance = (Reflectance)0;
    reflectance = ToonDiffuseReflectance(litData, lit, reflectance);
    reflectance = ToonSpecularReflectance(litData, lit, reflectance);
    reflectance = GetFresnel(litData, reflectance);
    reflectance = GetGi(litData, reflectance);

    const half3 color =
        reflectance.fresnel +
        reflectance.directDiffuse + reflectance.directSpecular +
        reflectance.indirectDiffuse + reflectance.indirectSpecular;

    return color;
}

#endif
