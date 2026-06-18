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
    float materialDebugMode;
    float lodTintOverlayMode;
    float4 lodTintColor;
    float4 highlightColor;
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
                              constant Uniforms& uniforms [[buffer(1)]],
                              texture2d<half> materialAtlas [[texture(0)]]) {
    constexpr sampler atlasSampler(address::clamp_to_edge, min_filter::nearest, mag_filter::nearest);

    float3 flatColor = in.color;
    half4 sampleColor = materialAtlas.sample(atlasSampler, in.uv);
    float3 texturedColor = in.color * float3(sampleColor.rgb);
    float2 tileCenterUV = floor(in.uv * 2.0) * 0.5 + float2(0.25, 0.25);
    half4 tileCenterSample = materialAtlas.sample(atlasSampler, tileCenterUV);
    float3 representativeFlatColor =
        (in.materialMode > 0.5)
        ? in.color * float3(tileCenterSample.rgb)
        : flatColor;

    float3 baseColor;
    if (uniforms.materialDebugMode > 1.5) {
        // Textures only: use sampled texture color, but keep a slight cool tint so the mode is
        // subtly and consistently distinguishable from hybrid.
        baseColor = texturedColor * float3(0.88, 0.94, 1.02);
    } else if (uniforms.materialDebugMode > 0.5) {
        // Flat only: collapse each material to a single representative color, not to gray. For
        // textured materials we sample the center of the atlas tile so the whole face becomes one
        // solid but still material-specific color.
        baseColor = representativeFlatColor * float3(1.02, 1.00, 0.98);
    } else {
        baseColor = (in.materialMode > 0.5) ? texturedColor : flatColor;
    }

    if (uniforms.lodTintOverlayMode > 0.5) {
        baseColor = mix(baseColor, uniforms.lodTintColor.rgb, uniforms.lodTintColor.a);
    }

    return float4(baseColor * in.lightAmount, 1.0);
}

struct HighlightVertexOut {
    float4 position [[position]];
};

struct HighlightVertexIn {
    float3 position [[attribute(0)]];
};

vertex HighlightVertexOut vertex_highlight(HighlightVertexIn in [[stage_in]],
                                           constant Uniforms& uniforms [[buffer(1)]]) {
    HighlightVertexOut out;
    out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);
    return out;
}

fragment float4 fragment_highlight(constant Uniforms& uniforms [[buffer(1)]]) {
    return uniforms.highlightColor;
}
