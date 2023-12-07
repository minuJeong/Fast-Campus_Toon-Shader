using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.Universal;

namespace Render.Runtime.RendererFeatures
{
    public class ToonRendererFeatures : ScriptableRendererFeature
    {
        private enum SamplerState
        {
            Outline,
        }

        private class OutlinePass : ScriptableRenderPass
        {
            private static readonly ShaderTagId TagId = new("Outline");
            private readonly ProfilingSampler _sampler = ProfilingSampler.Get(SamplerState.Outline);
            private FilteringSettings _filteringSettings;
            private DrawingSettings _drawingSettings;

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var desc = new RendererListDesc(TagId, renderingData.cullResults, renderingData.cameraData.camera)
                {
                    renderQueueRange = RenderQueueRange.all,
                    excludeObjectMotionVectors = true,
                };

                var rendererList = context.CreateRendererList(desc);
                var cmd = CommandBufferPool.Get("outline pass");
                using (new ProfilingScope(cmd, _sampler)) cmd.DrawRendererList(rendererList);

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        [SerializeField] private RenderPassEvent _event;
        private OutlinePass _outlinePass;

        public override void Create()
        {
            _outlinePass = new OutlinePass
            {
                renderPassEvent = _event,
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_outlinePass);
        }
    }
}