#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float3 color [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
};

struct Uniforms {
    float4x4 projection;
    float4x4 view;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);

    float3 lightDir = normalize(float3(0.5, -1.0, 0.2));
    float diff = max(dot(in.normal, -lightDir), 0.2);
    out.color = in.color * diff;

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
