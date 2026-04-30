import AppKit
import Metal
import MetalKit
import SwiftUI
import simd

struct AuroraView: NSViewRepresentable {
    func makeNSView(context: Context) -> AuroraMTKView { AuroraMTKView() }
    func updateNSView(_ nsView: AuroraMTKView, context: Context) {}

    static func dismantleNSView(_ nsView: AuroraMTKView, coordinator: ()) {
        nsView.shutdown()
    }
}

final class AuroraMTKView: MTKView {
    private var renderer: AuroraRenderer?

    init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            super.init(frame: .zero, device: nil)
            return
        }
        super.init(frame: .zero, device: dev)
        framebufferOnly = false
        wantsLayer = true
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.isOpaque = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        preferredFramesPerSecond = 60
        autoResizeDrawable = true
        renderer = AuroraRenderer(view: self)
        delegate = renderer
    }

    required init(coder: NSCoder) { fatalError() }

    func shutdown() { renderer = nil; delegate = nil }
}

private struct AuroraUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var _pad: Float = 0
}

final class AuroraRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()
    private var viewSize = SIMD2<Float>(0, 0)

    init?(view: MTKView) {
        guard let dev = view.device, let q = dev.makeCommandQueue() else { return nil }
        self.queue = q

        guard let lib = try? dev.makeLibrary(source: Self.shaderSource, options: nil),
              let vfn = lib.makeFunction(name: "aurora_vertex"),
              let ffn = lib.makeFunction(name: "aurora_fragment")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        let att = desc.colorAttachments[0]!
        att.pixelFormat = view.colorPixelFormat
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .one
        att.destinationAlphaBlendFactor = .one

        guard let ps = try? dev.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = ps

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = SIMD2(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        if viewSize.x == 0 || viewSize.y == 0 {
            viewSize = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        }
        guard viewSize.x > 0,
              let cmd = queue.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        var u = AuroraUniforms(resolution: viewSize, time: Float(CACurrentMediaTime() - startTime))
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<AuroraUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float time;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    // Single oversized triangle covers the viewport with no vertex buffer.
    vertex VOut aurora_vertex(uint vid [[vertex_id]]) {
        float2 pos = float2(
            (vid == 1) ? 3.0 : -1.0,
            (vid == 2) ? 3.0 : -1.0
        );
        VOut o;
        o.position = float4(pos, 0.0, 1.0);
        o.uv = pos * 0.5 + 0.5;
        return o;
    }

    static float3 hsv2rgb(float h, float s, float v) {
        float3 k = fract(float3(h) + float3(1.0, 2.0/3.0, 1.0/3.0));
        float3 p = abs(k * 6.0 - 3.0) - 1.0;
        return v * mix(float3(1.0), clamp(p, 0.0, 1.0), s);
    }

    static float ribbon(float2 uv, float baseline, float thickness,
                        float t, float seed) {
        float wave =
            0.045 * sin(uv.x * 2.3 + t * 0.35 + seed * 1.7) +
            0.028 * sin(uv.x * 5.7 - t * 0.55 + seed * 2.9) +
            0.018 * sin(uv.x * 11.3 + t * 0.85 + seed * 0.6) +
            0.011 * sin(uv.x * 19.1 - t * 1.10 + seed * 4.4);
        float thickMod = thickness * (1.0 + 0.30 * sin(uv.x * 1.4 + t * 0.20 + seed));
        float d = abs(uv.y - (baseline + wave));
        return exp(-(d * d) / (thickMod * thickMod));
    }

    fragment float4 aurora_fragment(VOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]]) {
        // Flip Y so baselines near 1.0 sit at the top of the view.
        float2 p = float2(in.uv.x, 1.0 - in.uv.y);
        float t = u.time;

        float topA = ribbon(p, 0.86, 0.060, t, 0.0);
        float topB = ribbon(p, 0.93, 0.035, t, 1.7);
        float botA = ribbon(p, 0.14, 0.060, t, 3.1);
        float botB = ribbon(p, 0.07, 0.035, t, 4.6);

        float hueTop = 0.58 + 0.10 * sin(p.x * 1.3 + t * 0.12);
        float hueBot = 0.78 + 0.10 * sin(p.x * 1.1 - t * 0.09);
        float3 cTop = hsv2rgb(hueTop, 0.80, 1.0);
        float3 cBot = hsv2rgb(hueBot, 0.75, 1.0);

        // Premultiplied alpha — pairs with the .one/.one blend on the pipeline.
        float aTop = topA * 0.55 + topB * 0.40;
        float aBot = botA * 0.55 + botB * 0.40;
        float3 rgb = cTop * aTop + cBot * aBot;
        float alpha = aTop + aBot;
        return float4(min(rgb, float3(1.0)), min(alpha, 1.0));
    }
    """
}
