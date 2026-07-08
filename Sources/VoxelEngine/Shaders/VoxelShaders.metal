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
    float fadeThreshold;        // 1.0 = fully drawn; < 1.0 = dither threshold
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);
    out.color = in.color;
    out.uv = in.uv;
    out.materialMode = in.materialMode;

    constexpr float3 lightDir = float3(0.44022545, -0.8804509, 0.17609018);
    out.lightAmount = max(dot(in.normal, -lightDir), 0.2);

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]],
                              texture2d<half> materialAtlas [[texture(0)]]) {
    // Screen-door dither for LOD crossfade. fadeThreshold = 1.0 means fully drawn;
    // values < 1.0 select a fraction of pixels via a 4x4 Bayer ordered dither matrix.
    // Old and new meshes draw together with complementary thresholds so they interleave
    // per pixel without blending — depth writes work correctly on both.
    if (uniforms.fadeThreshold < 1.0) {
        constexpr float bayer[16] = {  0.0/16,  8.0/16,  2.0/16, 10.0/16,
                                      12.0/16,  4.0/16, 14.0/16,  6.0/16,
                                       3.0/16, 11.0/16,  1.0/16,  9.0/16,
                                      15.0/16,  7.0/16, 13.0/16,  5.0/16 };
        uint2 pixel = uint2(in.position.xy) % 4;
        if (bayer[pixel.y * 4 + pixel.x] >= uniforms.fadeThreshold) {
            discard_fragment();
        }
    }

    constexpr sampler atlasSampler(
        address::clamp_to_edge,
        min_filter::linear,
        mag_filter::nearest,
        mip_filter::linear);
    const bool usesTextureMaterial = in.materialMode > 0.5;
    const bool texturesOnly = uniforms.materialDebugMode > 1.5;
    const bool flatColorsOnly = uniforms.materialDebugMode > 0.5 && uniforms.materialDebugMode <= 1.5;

    float3 flatColor = in.color;
    float3 texturedColor = flatColor;
    if (texturesOnly || (!flatColorsOnly && usesTextureMaterial)) {
        half4 sampleColor = materialAtlas.sample(atlasSampler, in.uv);
        texturedColor = in.color * float3(sampleColor.rgb);
    }

    float3 representativeFlatColor = flatColor;
    if (flatColorsOnly && usesTextureMaterial) {
        float2 tileCenterUV = floor(in.uv * 2.0) * 0.5 + float2(0.25, 0.25);
        half4 tileCenterSample = materialAtlas.sample(atlasSampler, tileCenterUV);
        representativeFlatColor = in.color * float3(tileCenterSample.rgb);
    }

    float3 baseColor;
    if (texturesOnly) {
        // Textures only: use sampled texture color, but keep a slight cool tint so the mode is
        // subtly and consistently distinguishable from hybrid.
        baseColor = texturedColor * float3(0.88, 0.94, 1.02);
    } else if (flatColorsOnly) {
        // Flat only: collapse each material to a single representative color, not to gray. For
        // textured materials we sample the center of the atlas tile so the whole face becomes one
        // solid but still material-specific color.
        baseColor = representativeFlatColor * float3(1.02, 1.00, 0.98);
    } else {
        baseColor = usesTextureMaterial ? texturedColor : flatColor;
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
