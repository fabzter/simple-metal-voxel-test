#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float3 color [[attribute(2)]];
    float2 uv [[attribute(3)]];
    float materialMode [[attribute(4)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
    float2 uv;
    float materialMode;
    float lightAmount;
};

struct Uniforms {
    float4x4 projection;
    float4x4 view;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);
    out.color = in.color;
    out.uv = in.uv;
    out.materialMode = in.materialMode;

    float3 lightDir = normalize(float3(0.5, -1.0, 0.2));
    out.lightAmount = max(dot(in.normal, -lightDir), 0.2);

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<half> materialAtlas [[texture(0)]]) {
    constexpr sampler atlasSampler(address::clamp_to_edge, min_filter::nearest, mag_filter::nearest);

    float3 baseColor = in.color;

    // Textured faces pay for the texture sample. Flat-color faces skip that fetch entirely,
    // which keeps the branch the user asked for when a simpler material is enough.
    if (in.materialMode > 0.5) {
        half4 sampleColor = materialAtlas.sample(atlasSampler, in.uv);
        baseColor *= float3(sampleColor.rgb);
    }

    return float4(baseColor * in.lightAmount, 1.0);
}
