/// The seams a benchmark turns, kept out of `g1455.dart`.
///
/// Each of these changes how the glass is drawn or exposes the host's plumbing
/// so a run can count it — none of them is something an application declares.
/// They are public because the research application that prices the package
/// lives in another package and has to reach them; an application that imports
/// this library is running an experiment.
library;

// Which spelling of the blend group's draw runs, and the cull inside its fold:
// the arms D189 and D170 were priced with. The defaults are the measured ones.
export 'src/surface/glass_group.dart'
    show
        GlassFusedTile,
        debugGlassFoldCull,
        debugGlassFusedSplit,
        debugGlassFusedSplitDefault,
        fusedDrawTiles,
        kGlassGroupShaderAsset,
        kMaxFusedTiles;
// The host's published proxy and its counters — `recorded`, `held` — which is
// what a report reads to say whether a frame captured.
export 'src/surface/glass_host.dart' show GlassProxyHandle, GlassProxyScope, kGlassRippleShaderAsset, kGlassShaderAsset;
// The ripple's model, which a test drives without a frame.
export 'src/surface/glass_ripple.dart' show GlassRippleField, GlassRippleWave;
// The anti-alias flag of the surface's draw, off by default since D200.
export 'src/surface/glass_surface.dart' show debugGlassShaderAntiAlias, debugGlassShaderAntiAliasDefault;
