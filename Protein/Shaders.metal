//
//  Shaders.metal
//  Protein
//
//  Created by Jana on 8/29/23.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
    float3 normals [[attribute(VertexAttributeNormals)]];
} Vertex;

// goes from vertex to fragment
typedef struct {
    float4 position [[position]];
    float4 color;
    float3 worldNormal;
    float3 worldPosition;
    float2 texCoord;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               // inastances array
                               constant PerInstanceUniforms *instances [[buffer(BufferIndexInstance)]],
                               // index of current instance
                               unsigned int instance [[instance_id]]) {
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    float4 worldPosition =  instances[instance].modelMatrix * position; // clip-space position
    out.worldPosition = worldPosition.xyz;
    out.worldNormal = in.normals;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.texCoord = in.texCoord;
    out.color = instances[instance].color;

    return out;
}

// ambient illumination
constant float3 ambientIntensity = 0.1;

// diffuse illumination
constant float3 lightPosition(2, 2, 2); // Light position in world space
constant float3 lightColor(1, 1, 1);

// Specular Illumination
constant float3 worldCameraPosition(0, 0, 2);
constant float specularPower = 200;

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]]) {
    
    // NOTE: This is for sampling from a texture
    //    constexpr sampler colorSampler(mip_filter::linear,
    //                                   mag_filter::linear,
    //                                   min_filter::linear);

    //    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy);
    //    return float4(colorSample);
    
    
    // diffuse illumination
    float3 N = normalize(in.worldNormal); // TODO: This should be a normal vector, i.e. in.normal.xyz
    float3 L = normalize(lightPosition - in.worldPosition); // NOTE: This should be 'world position' and not in.color. This isn't in.position either.
    float3 diffuseIntensity = saturate(dot(N, L));
    float3 V = normalize(worldCameraPosition - in.worldPosition);
    float3 H = normalize(L + V);
    float specularBase = saturate(dot(N, H));
    float specularIntensity = powr(specularBase, specularPower);
    
    float3 finalColor = saturate(ambientIntensity + diffuseIntensity) * in.color.xyz * lightColor + specularIntensity * lightColor;
    /*
    NOTE: 
    - color.xyz returns a float3(color.x, color.y, color.z). Can also do color.xy etc.
    - A half is a 16-bit float
    - in.position is the position of the interpolated vertex in CLIP SPACE. You want world-space.
    */
//    return in.color;
    return float4(finalColor, 1);
}
