/// Liquid Glass for Flutter.
///
/// Nothing here is stable yet. What is exported is what an application has to
/// *declare*, because the render tree does not carry it — plus the two ledgers
/// that turn those declarations into numbers somebody measured. The seams a
/// benchmark turns are in `glass_diagnostics.dart`, not here.
library;

export 'src/hardware.dart' show GlassHardware;
// The vocabulary of `GlassHost.thermal`. Reading the device is the
// application's: the package ships no platform code (D219).
export 'src/thermal.dart' show GlassThermalState;
// `ProxyBlurPass` only: the pipeline itself is not API — what an application
// declares about the blur is which spelling of the pass runs, and the host's
// two diagnostic arms need a name at the call site.
export 'src/proxy/proxy_pipeline.dart' show ProxyBlurPass;
// `GlassContentDeclaration` and the reason it produces: whether the host may
// hold a proxy nothing it watches has changed. Since D152 it declares nothing
// about content — the composited subtree answers that — and since D163 the
// holding side is the default, so what an application reaches for here is the
// opt-out. The oracle itself is not API — the host owns it — but the permission
// and the decision a report quotes are.
export 'src/proxy/proxy_retake.dart' show GlassContentDeclaration, GlassThermalPolicy, RetakeReason;
export 'src/proxy/proxy_resolution.dart'
    show
        ProxyCostModel,
        ProxyDamage,
        ProxyDivisorReason,
        ProxyResolution,
        ProxyResolutionChoice,
        ProxyResolutionPolicy,
        ProxyRouteCost;
export 'src/proxy/proxy_role.dart'
    show GlassProxy, GlassProxyPainter, GlassProxyRole, GradientProxyPainter, RenderGlassProxy, SolidProxyPainter;
// Level 3 of SS7.2 — and three names over one body, because everything that
// differs between them in this machine is the shape, the padding and the tap
// target. What a component adds is the label's colour, which is D178's law spent
// rather than restated.
export 'src/surface/glass_above.dart' show GlassAbove, RenderGlassAbove, kGlassModalLift;
export 'src/surface/glass_components.dart'
    show GlassBar, GlassButton, GlassCard, kGlassDisabledDarkLabel, kGlassDisabledLightLabel, kGlassMinTapTarget;
// Controls whose knob becomes a clear drop while held (spike 27): the drop
// exists only then, grows through `presence`, and moves inside a travel region.
export 'src/surface/glass_controls.dart'
    show
        GlassSlider,
        GlassSwitch,
        SliderGeometry,
        kGlassDisabledOpacity,
        kGlassDropDuration,
        kGlassDropOptics,
        kGlassDropScale,
        kGlassSwitchDropWiden,
        kGlassSwitchSize;
export 'src/surface/glass_scroll_edge.dart'
    show
        GlassScrollEdge,
        GlassScrollEdgeAppearance,
        GlassScrollEdgeSide,
        GlassScrollEdgeStyle,
        kGlassScrollEdgeDarkTint,
        kGlassScrollEdgeHardFill,
        kGlassScrollEdgeHardSigma,
        kGlassScrollEdgeLightTint,
        kGlassScrollEdgeSigma;
export 'src/surface/glass_segmented_control.dart'
    show GlassSegmentedControl, kGlassSegmentDropGrow, kGlassSegmentDropWiden, kGlassSegmentTrack;
export 'src/surface/glass_modal.dart'
    show
        GlassAlert,
        GlassAlertAction,
        GlassMenuAnchor,
        GlassMenuController,
        GlassMenuItem,
        GlassPopoverAnchor,
        kGlassAlertRadius,
        kGlassAlertWidth,
        kGlassMenuRadius,
        kGlassMenuRowHeight,
        kGlassMenuWidth,
        kGlassModalDim,
        kGlassSheetInset,
        kGlassSheetRadius,
        showGlassDialog,
        showGlassSheet;
export 'src/surface/glass_tab_bar.dart' show GlassTabBar, GlassTabItem, kGlassTabDropGrow, kGlassTabDropZoom;
export 'src/surface/glass_text_field.dart' show GlassTextField, kGlassFieldHeight;
export 'src/surface/glass_toolbar.dart'
    show GlassButtonGroup, GlassToolbarItem, kGlassToolbarHeight, kGlassToolbarItemWidth;
export 'src/surface/glass_finish.dart'
    show
        GlassFinish,
        GlassOptics,
        kAppleDimmingOpacity,
        kCalibratedRim,
        kHighContrastRimWidthLogical,
        kMaterialScaleDeltaE,
        kNonTextContrast,
        kRimWidthLogical,
        kTextContrastAA;
// The blend group: N surfaces drawn as one silhouette. The picture-side half of
// the grouping pair (roadmap phase B, research SS4.4); the capture-side half is
// not API at all, because it is a runtime decision about price.
export 'src/surface/glass_group.dart'
    show GlassBlendGroup, GlassGroup, GlassGroupScope, GlassUnion, RenderGlassGroup, kMaxFusedShapes, unionBlendRadius;
export 'src/surface/glass_host.dart' show GlassHost;
// The configuration level of the three-level structure (SS7.2), and the finish
// ladder it carries. Both are API by construction: the ladder has no automatic
// input at all, so the only way onto a rung below the top one is to say so.
export 'src/surface/glass_theme.dart' show GlassLegibility, GlassTheme, GlassThemeData;
export 'src/surface/glass_tier.dart' show GlassTier, GlassTierChoice, GlassTierPolicy, GlassTierReason;
// Where moving glass may go, so its motion costs no capture: the region is
// captured instead of the box, and a surface inside it samples the proxy
// already held.
export 'src/surface/glass_travel.dart' show GlassTravel, GlassTravelRegion, GlassTravelScope, RenderGlassTravel;
export 'src/surface/glass_ledger.dart'
    show
        GlassLedger,
        GlassLoad,
        GlassLoadVerdict,
        GlassScope,
        GlassSurfaceCluster,
        GlassSurfaceCostModel,
        GlassSurfaceGeometry,
        GlassSurfaceRecord;
// A wave from where the glass was touched (D229): opt-in, and not Apple's.
export 'src/surface/glass_ripple.dart' show GlassRipple, kMaxRippleWaves;
export 'src/surface/glass_surface.dart'
    show GlassFade, GlassSurface, RenderGlassSurface, debugPaintGlassSurfaces, kGlassCapsule;
