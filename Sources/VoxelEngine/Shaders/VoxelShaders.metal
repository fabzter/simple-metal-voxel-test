#include <metal_stdlib>
using namespace metal;

// ============================================================================
// Vertex / uniform layout
// ============================================================================

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
    float3 light;      // per-vertex lighting (sky ambient + sun), interpolated
    float fogFactor;   // 0 = clear, 1 = fully faded into the horizon color
};

// MUST match `Uniforms` in RenderTypes.swift field-for-field and in order. All fields
// after `fadeThreshold` are 16-byte-aligned (float4 / float4x4) so Swift and Metal agree
// on padding and the struct is binary-compatible across the language boundary.
struct Uniforms {
    float4x4 projection;
    float4x4 view;
    float materialDebugMode;
    float lodTintOverlayMode;
    float4 lodTintColor;
    float4 highlightColor;
    float fadeThreshold;        // 1.0 = fully drawn; < 1.0 = dither threshold

    // Atmosphere.
    float4x4 inverseViewProjection;  // NDC -> world, for the sky view ray
    float4 cameraPositionAndFog;     // xyz = camera world pos, w = fog density
    float4 sunDirection;             // xyz = normalized direction toward the sun
    float4 sunColor;                 // rgb = sunlight / sun-disk color
    float4 skyZenithColor;           // rgb = sky straight up
    float4 skyHorizonColor;          // rgb = horizon color (also the fog color)
    float4 groundColor;              // rgb = below-horizon + downward ambient bounce
};

// ============================================================================
// Shared atmosphere helpers
// ============================================================================

// Direction-based sky color: a horizon->zenith gradient above the horizon, fading to the
// ground color below it, plus a soft sun disk and glow. Used by the full-screen sky pass.
static inline float3 skyColor(float3 dir, constant Uniforms& u) {
    float up = dir.y;
    // pow() biases the gradient so most of the visible sky is the pleasant mid-blue and
    // the deep zenith color only appears when looking steeply upward.
    float3 above = mix(u.skyHorizonColor.rgb, u.skyZenithColor.rgb, pow(saturate(up), 0.5));
    float3 below = mix(u.skyHorizonColor.rgb, u.groundColor.rgb, pow(saturate(-up), 0.5));
    float3 base = up >= 0.0 ? above : below;

    // Sun disk (tight) + glow (broad) from the angle between the view ray and the sun.
    float d = max(dot(dir, normalize(u.sunDirection.xyz)), 0.0);
    float disk = smoothstep(0.9990, 0.9996, d);
    float glow = pow(d, 220.0) * 0.35 + pow(d, 24.0) * 0.12;
    return base + u.sunColor.rgb * (disk + glow);
}

// ============================================================================
// World (voxel) pass
// ============================================================================

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    // Mesh vertices are already in world space (there is no model matrix), so `in.position`
    // doubles as the world position we need for fog distance.
    out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);
    out.color = in.color;
    out.uv = in.uv;
    out.materialMode = in.materialMode;

    // Lighting: warm directional sun + hemispheric sky/ground ambient. Faces pointing up
    // catch sky color; faces pointing down catch a darker ground bounce. Computing this
    // per-vertex keeps it cheap and matches the project's readable, lightweight style.
    float3 normal = normalize(in.normal);
    float3 sunDir = normalize(uniforms.sunDirection.xyz);
    float diffuse = max(dot(normal, sunDir), 0.0);
    float hemi = normal.y * 0.5 + 0.5;  // 1 looking up, 0 looking down
    float3 ambient = mix(uniforms.groundColor.rgb, uniforms.skyZenithColor.rgb, hemi);
    out.light = ambient * 0.55 + uniforms.sunColor.rgb * (diffuse * 0.65);

    // Exponential-squared distance fog: near blocks stay crisp, far terrain melts into the
    // horizon color (which also hides distant LOD transitions).
    float distance = length(in.position - uniforms.cameraPositionAndFog.xyz);
    float f = distance * uniforms.cameraPositionAndFog.w;
    out.fogFactor = 1.0 - exp(-f * f);

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
        // Sample the center of the material's atlas tile. The atlas is a 4x2 grid, so map
        // the UV to its tile cell and take that cell's midpoint.
        float2 grid = float2(4.0, 2.0);
        float2 tileCenterUV = (floor(in.uv * grid) + 0.5) / grid;
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

    // Apply lighting, then blend toward the horizon/fog color by distance.
    float3 litColor = baseColor * in.light;
    float3 finalColor = mix(litColor, uniforms.skyHorizonColor.rgb, saturate(in.fogFactor));
    return float4(finalColor, 1.0);
}

// ============================================================================
// Sky pass (full-screen background gradient + sun)
// ============================================================================

struct SkyVertexOut {
    float4 position [[position]];
    float2 ndc;
};

// One oversized triangle that covers the whole screen, generated from the vertex id so no
// vertex buffer is needed. The extra area outside [-1,1] is simply clipped.
vertex SkyVertexOut vertex_sky(uint vertexID [[vertex_id]]) {
    float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 p = corners[vertexID];
    SkyVertexOut out;
    out.position = float4(p, 1.0, 1.0);  // z = far; sky depth state ignores depth anyway
    out.ndc = p;
    return out;
}

fragment float4 fragment_sky(SkyVertexOut in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    // Recover a world-space ray for this pixel by un-projecting two points along its
    // clip-space line and taking the direction between them.
    float4 nearW = uniforms.inverseViewProjection * float4(in.ndc, 0.0, 1.0);
    float4 farW = uniforms.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
    float3 rayDir = normalize(farW.xyz / farW.w - nearW.xyz / nearW.w);
    return float4(skyColor(rayDir, uniforms), 1.0);
}

// ============================================================================
// Selection highlight pass
// ============================================================================

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
