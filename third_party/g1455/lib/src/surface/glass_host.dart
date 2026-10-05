// The thing that runs the pipeline on a real screen.
//
// Everything under it has existed for several steps and been driven by tests.
// A host is what drives it in an application: it owns the register, the
// pipeline and the retake oracle, records after the frame that has just been
// painted, and publishes the result to the surfaces, which draw it on the
// frame after that.
//
// **The one-frame delay is structural, not a bug to be fixed later.** A capture
// reads the tree that was just painted, so the earliest a surface can show it
// is the following frame; that is what the roadmap prices as staleness (D30,
// D124) and it is why the first frame of any screen paints without a proxy.
// Both facts are counted rather than hoped for — a surface that never gets a
// proxy and one that gets a stale one look identical on a screenshot.
//
// What this deliberately does not do is choose *when* the frame happens. It
// records in a post-frame callback, because that is the only place the tree is
// both laid out and painted; the oracle decides whether to record at all.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../hardware.dart';
import '../thermal.dart';
import '../proxy/occlusion.dart';
import '../proxy/proxy_layer_watch.dart';
import '../proxy/proxy_pipeline.dart';
import '../proxy/proxy_resolution.dart';
import '../proxy/proxy_retake.dart';
import '../proxy/proxy_walk.dart';
import '../proxy/shadow_filter.dart';
import 'glass_above.dart';
import 'glass_finish.dart';
import 'glass_group.dart';
import 'glass_ledger.dart';
import 'glass_ripple.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';
import 'glass_tier.dart';

/// Where the package's own shader lives.
///
/// One key in every bundle: the pubspec declares it through `packages/g1455/`
/// and keeps the file under `lib/`, which the tool keys identically whether
/// this package is the root or a dependency (see `pubspec.yaml`).
const String kGlassShaderAsset = 'packages/g1455/shaders/glass_surface.frag';

/// The surface's shader with the ripple compiled in (D229).
const String kGlassRippleShaderAsset = 'packages/g1455/shaders/glass_surface_ripple.frag';

/// The current proxy, as something a surface can listen to.
///
/// A [Listenable] holding one frame, so a surface repaints when the proxy is
/// re-recorded and not when anything else happens. The frame's ownership stays
/// with the pipeline; this only points at it.
class GlassProxyHandle extends ChangeNotifier {
  GlassProxyFrame? _frame;
  GlassProxyFrame? get frame => _frame;

  /// The compiled shader, once it has arrived.
  ///
  /// Null until then, and a surface with a proxy and no program draws the
  /// **unrefracted** proxy rather than nothing — which is better than a flat
  /// tint and worse than glass, so it is counted separately
  /// (`RenderGlassSurface.paintsWithOptics`) rather than left to look like
  /// success on a screenshot.
  ui.FragmentProgram? get program => _program;
  ui.FragmentProgram? _program;
  set program(ui.FragmentProgram? value) {
    if (identical(value, _program)) {
      return;
    }
    _program = value;
    notifyListeners();
  }

  /// The compiled *group* shader, once it has arrived.
  ///
  /// A second program rather than a mode of the first, because adding a path to
  /// a runtime effect reprices every mode already in it by 52-62% (B5) and the
  /// lone surface is the common case. Loaded whether or not the screen has a
  /// group: a host that compiled it lazily would put the first frame of a
  /// fused toolbar on a different code path from every frame after it.
  ui.FragmentProgram? get groupProgram => _groupProgram;
  ui.FragmentProgram? _groupProgram;
  set groupProgram(ui.FragmentProgram? value) {
    if (identical(value, _groupProgram)) {
      return;
    }
    _groupProgram = value;
    notifyListeners();
  }

  /// The surface's program with the ripple compiled in, once something asked
  /// for it ([wantRippleProgram]) and it arrived.
  ///
  /// A third program for B5's reason, and loaded on demand rather than with
  /// the other two: a ripple is opt-in, and a screen that never declares one
  /// should not compile it. Until it arrives a touched surface draws the base
  /// program, which is the picture without the wave.
  ui.FragmentProgram? get rippleProgram => _rippleProgram ??= _cachedRippleProgram;
  ui.FragmentProgram? _rippleProgram;

  static ui.FragmentProgram? _cachedRippleProgram;
  static Future<ui.FragmentProgram>? _loadingRipple;

  /// Loads [rippleProgram], once per process, and notifies when it lands.
  void wantRippleProgram() {
    if (rippleProgram != null) {
      return;
    }
    (_loadingRipple ??= ui.FragmentProgram.fromAsset(kGlassRippleShaderAsset)).then((
      ui.FragmentProgram program,
    ) {
      _cachedRippleProgram = program;
      if (_rippleProgram == null && !_disposed) {
        _rippleProgram = program;
        notifyListeners();
      }
    });
  }

  bool _disposed = false;

  /// What the host declared its hardware to be.
  ///
  /// Carried here for the one choice a group makes at paint time that the host
  /// cannot make for it: whether the fused draw is split (D192). The sign of that
  /// lever differs between the families measured, so a group has to be told
  /// which one it is on, and the handle is what every group below a host holds.
  GlassHardware get hardware => _hardware;
  GlassHardware _hardware = GlassHardware.detect();
  set hardware(GlassHardware value) {
    if (value == _hardware) {
      return;
    }
    _hardware = value;
    notifyListeners();
  }

  /// How many frames have been published. The counter that tells a surface with
  /// no proxy apart from a surface whose proxy never updates.
  int get generation => _generation;
  int _generation = 0;

  /// How many rasterizations the pipeline has asked the engine for.
  ///
  /// Set by the host from `GlassProxyPipeline.snapshots`, because that is where
  /// they are taken. It is what gives [GlassHost.blurPass] an observable trace:
  /// `split` and `folded` publish the same picture from the same divisor at the
  /// same sigma, and a report carrying only the label would be recording what
  /// was asked for rather than what ran.
  int snapshots = 0;

  /// How many times the atlas layout has been repacked.
  ///
  /// Set from `GlassProxyPipeline.repacks` for the same reason [snapshots] is:
  /// the counter exists inside the pipeline and reached no report, so the one
  /// thing a retained layout is *for* was unobservable from outside. D41
  /// measured repacking every frame as the dominant cost of the whole route,
  /// and the ratio to [generation] is the reading — 1.0 means nothing is
  /// retained.
  ///
  /// It has a question waiting for it: on Adreno the route's UI-thread cost
  /// *grows* with the divisor (1005 µs at 1 against 1665 at 8, where the GPU's
  /// goes the other way, D156), and a layout that churns at small slot sizes
  /// would explain it. Nothing here claims that — the counter is what makes the
  /// claim checkable.
  int repacks = 0;

  /// How many entries the layer watch's last signature had, or 0 if it never
  /// ran.
  ///
  /// The trace the watch would otherwise not have, and without it a run that
  /// never walked would report as a walk that costs nothing — which is the
  /// shape `Picture.toImageSync(targetFormat:)` already cost this project once.
  /// Non-zero says the composited subtree was described; its size says how much
  /// of one.
  int watchedLayers = 0;

  /// How many frames the watch saw a change that missed every slot of the atlas.
  ///
  /// The trace of §4.2's question, and the reason it is a counter and not a
  /// boolean in a log: "a shared texture is a shared dirty flag" is an argument
  /// about a *rate*, and a mechanism that pays on 3% of frames and one that
  /// pays on 90% call for different designs. It is separately readable from
  /// [generation] on purpose — a report that only counted publishes could not
  /// tell a screen where nothing moved from one where everything moved away
  /// from the glass, and those are the two ends of the axis.
  int changesOutsideCapture = 0;

  /// Frames on which the GPU's texture limit moved the divisor, and frames on
  /// which nothing fit and no proxy was produced (D186).
  ///
  /// Set from `GlassProxyPipeline.ceilingDeepenings` and `ceilingRefusals`, and
  /// here for the reason every other counter on this handle is: the ceiling
  /// fires on a geometry nobody arranges on purpose — one oversized sheet on a
  /// desktop-sized window — so a report that did not carry it could not tell a
  /// run where it never fired from a run where it fired on every frame, and
  /// those look identical in every timing.
  ///
  /// [ceilingOverruns] is the third and it is the one that should never move:
  /// the search reasons about the layout before packing it, the check after the
  /// pack only refuses, and both can drop a frame. Non-zero means the reasoning
  /// was wrong, which is a bug report and not a measurement.
  int ceilingDeepenings = 0;
  int ceilingRefusals = 0;
  int ceilingOverruns = 0;

  /// Frames held across a change because thermal pressure bought the lag
  /// (D205), mirrored from the host so a report can read it beside
  /// [generation]: the two reset together, with the tree, and a throttle that
  /// never fired and one that fired every frame are otherwise the same run.
  int throttled = 0;

  /// Declares a change nothing above the content is painted for.
  ///
  /// The escape hatch that makes [GlassContentDeclaration.declared] usable, and
  /// it is now the *last* resort rather than the first: the host observes a
  /// scroll (D147) and its own repaint, which between them cover every change
  /// that is not behind a nested repaint boundary. What is left is content that
  /// repaints inside one — and [GlassChangingContent] is the same thing said by
  /// placement instead of by timing, which is usually the honest way round.
  ///
  /// Reach it with `GlassProxyScope.maybeOf(context)?.noteChange()`.
  ///
  /// Free under [GlassContentDeclaration.undeclared], where the proxy is
  /// re-recorded anyway, and the difference between a working screen and a
  /// frozen one under the default.
  void noteChange() => _changes.notify();

  /// Fires when [noteChange] is called. The host listens; nothing else should.
  Listenable get changes => _changes;
  final _HandleChanges _changes = _HandleChanges();

  @override
  void dispose() {
    _disposed = true;
    _changes.dispose();
    super.dispose();
  }

  void publish(GlassProxyFrame? frame) {
    if (identical(frame, _frame)) {
      return;
    }
    _frame = frame;
    _generation++;
    notifyListeners();
  }

  /// The proxies of glass that stands on glass, by level: `upper[0]` is what
  /// the surfaces one glass deep sample, and so on up.
  ///
  /// A level apart from [frame] rather than more slots in it, because what a
  /// level captures *contains* the level below it drawn — the lens over a tab
  /// bar has to see the bar's glass and its icons — so it can only be recorded
  /// once the level below has been published. See `GlassHost` for the walk.
  List<GlassProxyFrame?> get upper => _upper;
  List<GlassProxyFrame?> _upper = const <GlassProxyFrame?>[];

  /// Publishes the levels above [frame]. Not a new generation: they are the
  /// same capture, finished.
  ///
  /// Silent when nothing changed, as [publish] is: the host publishes the
  /// levels on every frame that has nothing to capture, and a notification
  /// there repaints every surface at presence zero, whose repaint is the next
  /// frame — a screen whose only glass was a resting drop (a segmented
  /// control, a switch) never settled.
  void publishUpper(List<GlassProxyFrame?> frames) {
    if (listEquals(frames, _upper)) {
      return;
    }
    _upper = List<GlassProxyFrame?>.unmodifiable(frames);
    notifyListeners();
  }

  /// The frame that holds [key]'s slot: the base one, or the level it stands
  /// at. The base one when none does, so that the caller's `slotForKey` says
  /// "not in this frame" exactly as it did before there were levels.
  GlassProxyFrame? frameFor(Object key) {
    final GlassProxyFrame? base = _frame;
    if (_upper.isEmpty || (base != null && base.keys.contains(key))) {
      return base;
    }
    for (final GlassProxyFrame? frame in _upper) {
      if (frame != null && frame.keys.contains(key)) {
        return frame;
      }
    }
    return base;
  }
}

/// The application's own change declarations, as something the host can watch.
///
/// Shaped like `RenderGlassProxy.proxyChanges` on purpose: the oracle already
/// subscribes to that, so a second input to the same decision is the same kind
/// of thing rather than a second mechanism.
class _HandleChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Carries the current proxy down the tree.
class GlassProxyScope extends InheritedWidget {
  const GlassProxyScope({required this.handle, required super.child, super.key});

  final GlassProxyHandle handle;

  static GlassProxyHandle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassProxyScope>()?.handle;

  @override
  bool updateShouldNotify(GlassProxyScope oldWidget) => oldWidget.handle != handle;
}

/// Owns the whole proxy pipeline for one screen.
///
/// Put it above everything the glass is meant to show. Its child is the screen:
/// the register finds the surfaces inside it, the pass reads it, and the
/// surfaces sample the result.
class GlassHost extends StatefulWidget {
  const GlassHost({
    required this.child,
    this.hardware,
    this.finish,
    this.tier = GlassTierChoice.byDefault,
    this.backdrop,
    this.highContrast,
    this.richBackdrop = false,
    this.minLabelContrast,
    this.ripple,
    this.thermal,
    this.thermalPolicy = const GlassThermalPolicy(),
    this.budgetDeltaE = ProxyResolutionPolicy.defaultDamageBudgetDeltaE,
    this.shadowFilter,
    this.occlusion,
    this.resolution,
    this.maxCaptures,
    this.maxTextureSide,
    this.blurPass,
    this.content = GlassContentDeclaration.byDefault,
    super.key,
  });

  final Widget child;

  /// Whose measurements apply. Defaults to what the platform can be asked —
  /// Apple platforms answer, everything else is [GlassHardware.unmeasured]
  /// (D121), which gets the same divisor and the same merging as a declared
  /// family and a null where the price would be (D136).
  final GlassHardware? hardware;

  /// The optics every surface under this host wears unless it names its own.
  ///
  /// Its `name` is the key into the measured damage tables and its sigma
  /// decides the bleed, the residual blur and — through the budget — the retake
  /// ceiling. So a finish nobody has graded gets refusals rather than numbers,
  /// which is the intended behaviour.
  ///
  /// Null is Apple's `.regular`, which is two materials (D230):
  /// [GlassFinish.regular] picks [GlassFinish.regularDark] or
  /// [GlassFinish.regularLight] from [backdrop] and the platform's appearance,
  /// and the host follows the appearance as it changes. Name either branch to
  /// hold it — a dark glass on a light screen is a choice Apple's material
  /// does not make, and this is where an application makes it.
  final GlassFinish? finish;

  /// Which rung of phase D's ladder every surface under this host draws.
  ///
  /// [GlassTier.full] and its reasons are in `glass_tier.dart`; the short
  /// version is that the ladder has no automatic input, so this is a
  /// declaration and the package supplies no default but the top rung.
  ///
  /// Below the top rung the whole pipeline goes quiet: nothing under this host
  /// reads a proxy, so nothing is captured, no atlas is packed and no shader is
  /// sampled. The host still mounts — its register still counts the glass,
  /// because the translucency tax does not care which rung drew it — and
  /// [recorded] stays at zero, which is the observable the requirement is
  /// stated in (D58: the cheap finish reads no backdrop at all).
  final GlassTierChoice tier;

  /// What is behind the glass on this screen, on average.
  ///
  /// Installed into the theme, and read by [GlassTier.opaque] alone — see
  /// [GlassThemeData.backdrop] for why the bottom rung is the only one that
  /// cannot work it out for itself.
  final Color? backdrop;

  /// The platform's increase-contrast switch, or null to read it from
  /// `MediaQuery.highContrastOf` — which the engine sets on iOS and on Android
  /// 34+, and **never on macOS**, where the application has to read
  /// `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` itself and pass
  /// it (D202). See [GlassThemeData.highContrast] for what it draws.
  final bool? highContrast;

  /// Whether the screen under the glass is an image rather than a colour. See
  /// [GlassThemeData.richBackdrop].
  final bool richBackdrop;

  /// The least contrast a component label must reach, met by dimming the glass
  /// when the finish cannot reach it. See [GlassThemeData.minLabelContrast].
  final double? minLabelContrast;

  /// The wave every surface below makes when touched, or null for none — the
  /// platform's behaviour. See [GlassThemeData.ripple] and [GlassRipple].
  final GlassRipple? ripple;

  /// The device's thermal state, as the application read it — the package
  /// ships no platform code to read it (D219). Null is nominal.
  ///
  /// Spent by [thermalPolicy] on the retake, never on the ladder: under
  /// pressure a changing screen may be captured less often, by as many frames
  /// as the finish's own staleness price allows (D205).
  final GlassThermalState? thermal;

  /// What each thermal state may spend on staleness. [GlassThermalPolicy.never]
  /// keeps every frame fresh whatever the device says.
  final GlassThermalPolicy thermalPolicy;

  /// The whole quality allowance, in ΔE against the same finish at full
  /// quality. 1% of the distance between two of Apple's own materials (S4).
  ///
  /// One number for both axes, because D124 measured that they compose rather
  /// than add: the divisor is chosen against it and the retake ceiling is what
  /// is left afterwards. It reached only the second of those for one release,
  /// which made a raised budget hold the proxy longer without ever recording it
  /// smaller.
  final double budgetDeltaE;

  /// Whether this screen may hold a proxy nothing under it has changed.
  ///
  /// **The default holds, since D163** — which is the largest lever this
  /// package has anywhere (79.4% and 66.3% of the addition on Adreno, 97.8% on
  /// Metal, D146) and the only one the capture has at all, the capture being
  /// 77% of what the route adds at the divisor the policy picks on a dpr-2
  /// screen (D141) where the proxy's resolution buys the other 23% (D140).
  ///
  /// It was the other way round for three days, and what moved it is not a new
  /// measurement of the lever but the two things that used to stand against it:
  /// the application was being asked to promise something nobody can verify
  /// (D152 replaced the promise with a walk of the composited subtree), and the
  /// walk's own price was unknown (D160 put it under 3 µs a frame, below what a
  /// device run resolves). What is left of the risk lives in one table of layer
  /// types, and that table is now checked against the SDK's `layer.dart`
  /// (D162).
  ///
  /// Pass [GlassContentDeclaration.undeclared] to go back to re-recording every
  /// frame — for a host compositing through something it thinks this package
  /// misreads, or for a benchmark arm that wants the capture on every frame.
  final GlassContentDeclaration content;

  /// The one content policy M11 left alive: shadows cost 0.00 ΔE to skip (D31).
  ///
  /// Null means "draw them", which is the conservative default rather than the
  /// cheap one — half of `ShadowFilter` is a heuristic (anything painted
  /// through a `MaskFilter` is *usually* a shadow), and a design that blurs a
  /// highlight on purpose would lose it silently.
  final ShadowFilter? shadowFilter;

  /// Where the descent may stop, if the application has worked it out.
  final OcclusionPolicy? occlusion;

  /// The proxy divisor, named by the host instead of chosen from the tables.
  ///
  /// Null is the normal case and the one every application should use: the
  /// policy trades measured quality against measured price and says which of
  /// the four things stopped it. This overrides that, and it exists because the
  /// tables cannot be checked without it — see
  /// [ProxyDivisorReason.pinnedByHost]. It is the same shape as [hardware]:
  /// something the package cannot work out, declared by whoever can.
  final ProxyResolution? resolution;

  /// Stops recording after this many captures. Null records for ever, which is
  /// the only shipping behaviour.
  ///
  /// **A diagnostic seam, and it exists because of one measurement.** On
  /// Xclipse our glass step spends 28.5 ms per frame *waiting* while its raster
  /// thread takes 1.68 ms and the GPU sits at 54% busy — idle nearly half the
  /// time while dropping more than half the frames (D133). Three things could
  /// do that and only one of them is the capture: the capture's own submission,
  /// the shader sampling a proxy texture sixteen times larger at a divisor of 1,
  /// and the governor never ramping. Pinning the count separates the first from
  /// the second, because a held proxy is still sampled every frame at exactly
  /// the same size — the shader's work does not change, the recording stops.
  ///
  /// Setting it makes the picture wrong on purpose: the proxy goes stale for
  /// ever, which is a cost experiment and never a mode. `held` and `recorded`
  /// are what say which happened.
  final int? maxCaptures;

  /// How the residual blur reaches the atlas — and, at [ProxyBlurPass.none],
  /// whether it reaches it at all. The second diagnostic on this widget, and at
  /// that value the same shape as [maxCaptures]: it makes the picture wrong on
  /// purpose, so it is a cost experiment and never a mode.
  ///
  /// [ProxyBlurPass.folded] is the exception — it draws the same picture to
  /// within a code value (spike #21) — and since 2026-09-11 it is not held back
  /// either: its price is measured on both families, the sign differs between
  /// them, and null here takes [ProxyBlurPass.defaultFor], which reads the
  /// hardware declaration. Naming one overrides that.
  ///
  /// The axis exists because D139 found a knee the route's price has no model for —
  /// the addition falls 0.94 and 0.65 ms across the first two intervals of the
  /// divisor and then **0.05** across the third — and the only mechanism anyone
  /// has for it is arithmetic rather than a measurement: on Metal the capture is
  /// scale-free (D119), so the divisor buys only what happens after it, and this
  /// pass's sigma in texels falls to 0.58 at a divisor of 8, where Impeller's
  /// truncation radius `(σ − 0.5)·√3` is 0.13 of a texel. Turning it off splits
  /// "the blur ran out" from "the bandwidth ran out"; nothing else does, because
  /// both follow the proxy and neither has a counter.
  ///
  /// Not a finish of sigma 0, which would be a different material and would
  /// change the shader as well as the pass.
  final ProxyBlurPass? blurPass;

  /// The largest texture this GPU will actually allocate, in device pixels a
  /// side. Null takes [GlassHardware.maxTextureSide], which is a specification
  /// floor rather than a reading of the device.
  ///
  /// Worth declaring on a large screen and pointless on a phone: it is what
  /// stops the atlas from being handed to a `toImageSync` that would silently
  /// rescale it (`AtlasLayout.fitsTexture`), and the package's only answer to
  /// hitting it is a coarser proxy. A host that knows its device reports 16384
  /// and says so keeps the quality the floor of 4096 would have spent.
  final int? maxTextureSide;

  @override
  State<GlassHost> createState() => _GlassHostState();
}

class _GlassHostState extends State<GlassHost> {
  final GlassLedger _ledger = GlassLedger();

  /// What actually establishes that nothing changed, when the host is allowed
  /// to hold at all.
  ///
  /// The observations above it — a scroll, this host's own repaint, a marker —
  /// are cheap and correct and *incomplete*: each of them stops at a nested
  /// repaint boundary, and the corpus says a realistic screen crosses 8 to 15
  /// of those. This one cannot be hidden from, because a repaint mints new
  /// pictures in whichever layer owns it and the one change that repaints
  /// nothing (D151) is a property of a retained layer. It runs only where
  /// holding is possible: under the default declaration the proxy is re-recorded
  /// anyway and the walk would be pure cost.
  final ProxyLayerWatch _watch = ProxyLayerWatch();

  /// The same walk with only the glass *draws* excluded, advanced only inside
  /// the watch's assertion and so only in debug.
  ///
  /// The assertion is about the table, and the table is what both walks share;
  /// what excluding a whole surface adds is a second reason for "no change"
  /// that is not a hole. A repaint of the host's boundary mints its new
  /// pictures wherever its dirty children paint, and when every one of them is
  /// inside glass — a label in a bar changing, with nothing of the boundary's
  /// own painted outside the glass — the oracle's walk is right to see nothing:
  /// none of it is in the proxy. The first application built on the package did
  /// exactly that on its first tap, after a corpus of scenes that never had
  /// (D219).
  ///
  /// Not a walk with nothing excluded, which is the obvious version and has no
  /// teeth: a draw layer is a type the table does not read, so it reports a
  /// change on every frame and the assertion could never fire while any glass
  /// was on the screen. This one is weaker than the oracle's walk on one kind
  /// of frame: a publish repaints a surface, and with it the content inside, so
  /// right after one the content walk changes and a hole elsewhere would pass.
  /// On every frame without a publish it is as quiet as the oracle's — the
  /// steady state, where a held proxy is what is at stake.
  final ProxyLayerWatch _debugWatchContent = ProxyLayerWatch();

  /// Whether the framework painted this host's subtree during the frame just
  /// ended. Read by the watch's own assertion and cleared with every capture.
  bool _framePainted = false;
  final GlassProxyHandle _handle = GlassProxyHandle();
  final GlobalKey _rootKey = GlobalKey();
  late GlassProxyPipeline _pipeline;
  late RetakeOracle _oracle;
  bool _scheduled = false;

  /// Frames that were recorded, and frames that were held. Counted because a
  /// policy that quietly records every frame looks exactly like one that works.
  int recorded = 0;
  int held = 0;

  /// Of [held], the frames held across a change because thermal pressure bought
  /// the staleness (D205). Counted apart because it is the one hold that knows
  /// its picture is out of date.
  int throttled = 0;

  /// How many [GlassProxy] markers the oracle is subscribed to.
  ///
  /// Exposed for the same reason [recorded] and [held] are: a subscription that
  /// never happened and one that found nothing to subscribe to look identical
  /// from outside, and until 2026-09-09 the first was the truth — the host built
  /// an oracle, handed it to the pipeline every frame, and never called
  /// [RetakeOracle.watch]. Every marker in every application was inert.
  int get watchedMarkers => _oracle.watchedMarkers;

  /// Whether the marker subscription has to be rebuilt before the next capture.
  ///
  /// The walk is `visitChildren` over the whole subtree — 24 us per pass on the
  /// corpus (M12) — so it runs when the tree's *structure* changes rather than
  /// every frame. The ledger is the signal: it notifies exactly when a surface
  /// arrives or leaves and never on geometry, because it stores surfaces rather
  /// than their rects.
  ///
  /// It is a proxy for the real event and not the event: a subtree can gain a
  /// marker without a surface arriving, and that marker stays unwatched until
  /// something else moves. What that costs is bounded rather than unbounded —
  /// the oracle falls back to its ceiling — and the honest fix is for markers to
  /// register themselves the way surfaces do, which is API this package does not
  /// have yet.
  bool _markersStale = true;

  GlassHardware get _hardware => widget.hardware ?? GlassHardware.detect();

  /// [GlassHost.finish], or the branch of `.regular` the screen is on. Set
  /// before the first [_build], from [didChangeDependencies]: the appearance
  /// is inherited, and `initState` may not read it.
  late GlassFinish _finish;

  GlassFinish _resolveFinish() =>
      widget.finish ??
      GlassFinish.regular(
        appearance: MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
        backdrop: widget.backdrop,
      );

  static ui.FragmentProgram? _cachedProgram;
  static Future<ui.FragmentProgram>? _loading;
  static ui.FragmentProgram? _cachedGroupProgram;
  static Future<ui.FragmentProgram>? _loadingGroup;

  @override
  void initState() {
    super.initState();
    _ledger.addListener(_markersChanged);
    // Through a closure rather than `_oracle.noteChange` directly: the oracle is
    // rebuilt whenever the finish, the budget or the declaration changes, and a
    // listener bound to the old one would declare changes to a dead object.
    _handle.changes.addListener(_noteDeclaredChange);
    _loadProgram();
    _loadGroupProgram();
  }

  void _noteDeclaredChange() => _oracle.noteChange();

  /// A surface arrived or left, so the subtree is a different subtree.
  void _markersChanged() => _markersStale = true;

  /// Compiles the shader once per process.
  ///
  /// `FragmentProgram.fromAsset` is a future, and it is the one engine future a
  /// widget test's fake clock does complete — it comes over the asset channel,
  /// which the binding pumps. Everything else on that list hangs until the
  /// ten-minute timeout.
  void _loadProgram() {
    final ui.FragmentProgram? cached = _cachedProgram;
    if (cached != null) {
      _handle.program = cached;
      return;
    }
    (_loading ??= ui.FragmentProgram.fromAsset(kGlassShaderAsset)).then((
      ui.FragmentProgram program,
    ) {
      _cachedProgram = program;
      if (mounted) {
        _handle.program = program;
      }
    });
  }

  /// The same, for the fused draw.
  ///
  /// Loaded unconditionally rather than when a group appears: a program
  /// compiled on the frame a toolbar first fuses would put that frame on a
  /// different path from every frame after it, and the first frame of an
  /// animation is the one somebody screenshots.
  void _loadGroupProgram() {
    final ui.FragmentProgram? cached = _cachedGroupProgram;
    if (cached != null) {
      _handle.groupProgram = cached;
      return;
    }
    (_loadingGroup ??= ui.FragmentProgram.fromAsset(kGlassGroupShaderAsset)).then((
      ui.FragmentProgram program,
    ) {
      _cachedGroupProgram = program;
      if (mounted) {
        _handle.groupProgram = program;
      }
    });
  }

  /// The first build, and a rebuild when the appearance moves `.regular` to
  /// its other branch — which is a different finish exactly as a new
  /// [GlassHost.finish] is.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GlassFinish resolved = _resolveFinish();
    if (!_built) {
      _finish = resolved;
      _built = true;
      _build();
    } else if (resolved != _finish) {
      _finish = resolved;
      _rebuild();
    }
  }

  bool _built = false;

  void _build() {
    _handle.hardware = _hardware;
    _pipeline = _newPipeline();
    _oracle = RetakeOracle(
      finish: _finish.name,
      budgetDeltaE: widget.budgetDeltaE,
      content: widget.content,
    );
    // A new oracle watches nothing, whatever the old one watched.
    _markersStale = true;
  }

  GlassProxyPipeline _newPipeline() => GlassProxyPipeline(
    finishSigmaLogical: _finish.blurSigmaLogical,
    hardware: _hardware,
    finish: _finish.name,
    shadowFilter: widget.shadowFilter,
    occlusion: widget.occlusion,
    damageBudgetDeltaE: widget.budgetDeltaE,
    pinnedResolution: widget.resolution,
    maxTextureSide: widget.maxTextureSide,
    blurPass: widget.blurPass,
  );

  @override
  void didUpdateWidget(GlassHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final GlassFinish resolved = _resolveFinish();
    final bool finishMoved = resolved != _finish;
    _finish = resolved;
    if (finishMoved ||
        widget.budgetDeltaE != oldWidget.budgetDeltaE ||
        widget.resolution?.divisor != oldWidget.resolution?.divisor ||
        widget.maxCaptures != oldWidget.maxCaptures ||
        widget.blurPass != oldWidget.blurPass ||
        widget.maxTextureSide != oldWidget.maxTextureSide ||
        widget.content != oldWidget.content ||
        _hardware != (oldWidget.hardware ?? GlassHardware.detect())) {
      _rebuild();
    }
  }

  /// A different finish is a different bleed, a different divisor and a
  /// different ceiling. Rebuilt rather than mutated: the retained layout is
  /// sized for the old one, and holding it would be holding slots for a texel
  /// that no longer exists.
  void _rebuild() {
    _handle.publish(null);
    _publishUpper(const <GlassProxyFrame?>[]);
    _pipeline.dispose();
    _oracle.dispose();
    _build();
  }

  @override
  void dispose() {
    _handle.publish(null);
    _publishUpper(const <GlassProxyFrame?>[]);
    _pipeline.dispose();
    _oracle.dispose();
    _handle.changes.removeListener(_noteDeclaredChange);
    _handle.dispose();
    _ledger
      ..removeListener(_markersChanged)
      ..dispose();
    super.dispose();
  }

  /// Records after the frame that has just been painted, and arms itself again.
  ///
  /// A post-frame callback rather than anything inside `paint`: the tree has to
  /// be laid out *and* painted before a capture means anything, and driving a
  /// pass from inside another node's paint is the reentrancy the walk was
  /// deliberately kept out of (M12).
  ///
  /// **Re-armed from inside the callback, not from `build`**, and the first
  /// version did the latter. `build` runs when something rebuilds the host, not
  /// when a frame is produced — so a screen that scrolls without rebuilding the
  /// host, which is most of them, got exactly one capture and then a proxy
  /// frozen forever. What caught it was not a test: it was a **deliberate break
  /// that failed to break**. Deleting the self-capture rule left every arm
  /// passing, because with only one capture there is no second one to feed on.
  ///
  /// Re-arming costs nothing when the app is idle: `addPostFrameCallback` does
  /// not request a frame, it waits for the next one that happens anyway. And
  /// the oracle, not this, decides whether anything is recorded.
  void _scheduleCapture() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }
      _capture();
      // After the capture, because the capture is what reads it, and outside
      // `_capture` because that method has early returns and a flag left set
      // would fire the watch's assertion on a later frame.
      _framePainted = false;
      _scheduleCapture();
    });
  }

  void _capture() {
    final int? limit = widget.maxCaptures;
    if (limit != null && recorded >= limit) {
      // Counted as held rather than skipped: from the surface's point of view
      // this frame is exactly a frame the oracle declined to retake, and the
      // report should not have to know which of the two decided.
      held++;
      return;
    }
    final RenderObject? root = _rootKey.currentContext?.findRenderObject();
    if (root == null) {
      return;
    }
    if (_markersStale) {
      // Before the decision, not after: the oracle's first `decide` of this
      // frame has to be able to see a marker that fired since the last one.
      _oracle.watch(root);
      _markersStale = false;
    }
    final List<GlassSurfaceGeometry> keys = _ledger.registered.toList();
    // A fused silhouette reaches past its members' boxes, so each member is
    // captured with that much more around it (D201). Per member rather than
    // as the cluster's quad: the silhouette lies within the reach of *some*
    // member's shape, and the quad of a scattered group is mostly empty.
    final reachOf = <GlassSurfaceGeometry, double>{
      for (final GlassSurfaceCluster cluster in _ledger.clusters)
        if (cluster.bridgeReach > 0)
          for (final GlassSurfaceGeometry member in cluster.members) member: cluster.bridgeReach,
    };
    final rects = <Rect>[];
    final present = <GlassSurfaceGeometry>[];
    final finishes = <GlassFinish>[];
    final view = View.maybeOf(context);
    final Rect? viewport = view == null ? null : Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final candidates = <({GlassSurfaceGeometry surface, GlassSurfaceRecord record, GlassFinish finish, double reach})>[];
    var samplingMargin = 0.0;
    for (final GlassSurfaceGeometry surface in keys) {
      final GlassSurfaceRecord? record = surface.readGeometry();
      // A surface below the top rung is in the register and not in the capture:
      // it pays the translucency tax like any other translucent fill (D21, D26)
      // and reads nothing, so charging the atlas for it would pay for a
      // snapshot no shader will ever sample.
      //
      // Nor is a surface at presence zero, which draws nothing: capturing it
      // would size the atlas — and, for a finish of its own, the divisor — for
      // glass that is not there (a control's drop at rest).
      if (record != null && record.tier.readsBackdrop && record.presence > 0 && record.materialize > 0) {
        final GlassFinish finish = record.finish ?? _finish;
        final double reach = (reachOf[surface] ?? 0) + finish.optics.reach(record.rect.size / 2);
        // Keep offscreen glass that could still be sampled by visible glass.
        // 2.5 sigma is the atlas pipeline's own blur context requirement.
        final double margin = reach + finish.blurSigmaLogical * 2.5;
        if (margin > samplingMargin) samplingMargin = margin;
        candidates.add((surface: surface, record: record, finish: finish, reach: reach));
      }
    }
    final Rect? visible = viewport?.inflate(samplingMargin);
    for (final candidate in candidates) {
        final record = candidate.record;
        if (visible != null && visible.isFinite && !visible.isEmpty &&
            !record.rect.inflate(reachOf[candidate.surface] ?? 0).overlaps(visible)) {
          continue;
        }
        // A widened or minifying glass samples past its box (D218); by its
        // full reach rather than the presence-scaled one, so a drop lifting in
        // does not change the capture's input on every frame of it.
        rects.add(
          record.captureRect.inflate(
            candidate.reach,
          ),
        );
        present.add(candidate.surface);
        finishes.add(candidate.finish);
    }
    if (rects.isEmpty) {
      // Nothing reads a proxy, so nothing is recorded — which is how "the cheap
      // finish does not read the backdrop at all" (D58) is enforced rather than
      // promised: there is no image for a surface to sample even by mistake.
      _handle.publish(null);
      _publishUpper(const <GlassProxyFrame?>[]);
      // A retained subtree can return at the exact last-captured position.
      // Its layers/rects then compare equal, but the displayed frame was
      // cleared above. Force that first visible frame to be published again.
      _oracle.noteChange();
      return;
    }
    // What each slot is blurred by is an input to the capture the oracle
    // cannot see — it watches rectangles — and a surface that changes it in
    // place (materializing, or a finish swapped on a still panel) would be
    // held at its old blur. Compared as the list the pipeline is given.
    final blurs = <double>[for (final GlassFinish f in finishes) f.blurSigmaLogical];
    if (!listEquals(blurs, _lastBlurs)) {
      _lastBlurs = blurs;
      _oracle.noteChange();
    }
    final _Levels levels = _Levels.of(present, root);
    if (widget.content != GlassContentDeclaration.undeclared) {
      _noteCompositedChanges(root, keys, levels);
    }
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? View.maybeOf(context)?.devicePixelRatio ?? 1;
    _oracle.throttleFrames = widget.thermalPolicy.throttleFrames(
      _finish.name,
      widget.thermal,
      spentDeltaE: _oracle.spentDeltaE,
    );
    final _Level base = levels.select(0, present, rects, finishes, _finish);
    final ({GlassProxyFrame? frame, RetakeReason reason}) result = _pipeline.captureIfNeeded(
      root,
      base.rects,
      devicePixelRatio: dpr,
      oracle: _oracle,
      keys: base.keys,
      fused: _fusedGrouping(base.keys),
      // Only when some surface wears another finish: a screen of one finish
      // takes the path it always took, bit for bit.
      finishes: base.mixed ? base.finishes : null,
      // The levels above are recorded on this decision, so it watches them too.
      // Not where glass that bears glass actually is: a bar resized inside its
      // travel is already seen by the layer watch — its relayout repaints the
      // content it bears or moves the layers it positions — and watching its
      // rect as well broke no arm when removed (D218).
      watched: levels.top > 0 ? rects : null,
    );
    // Read whether or not anything was published: a held frame takes no
    // snapshot, and a counter that only moved on publishes could not say so.
    _readCounters();
    if (result.reason.holds) {
      held++;
      if (result.reason == RetakeReason.throttled) {
        throttled++;
        _handle.throttled = throttled;
      }
      return;
    }
    recorded++;
    _handle.publish(result.frame);
    _captureUpper(root, levels, present, rects, finishes, dpr);
    _readCounters();
  }

  /// Records the levels of glass that stand on glass, bottom up, each one
  /// after the level below it has been published — because what a level
  /// captures is the level below *drawn*: the walk paints every glass under
  /// it through the surface's own frame (`RenderGlassSurface._paintIntoProxy`)
  /// and skips its own level and everything above, which is the self-capture
  /// rule said per level.
  ///
  /// Recorded whenever the base is, and never otherwise: the oracle watches
  /// every level's surfaces, so a base that holds is a screen on which no
  /// level has anything new to show. The price is one more snapshot per level
  /// on every recorded frame of a screen that has one, and nothing on a screen
  /// that does not.
  void _captureUpper(
    RenderObject root,
    _Levels levels,
    List<GlassSurfaceGeometry> present,
    List<Rect> rects,
    List<GlassFinish> finishes,
    double dpr,
  ) {
    final previous = _handle.upper;
    if (levels.top == 0 && previous.isEmpty) {
      return;
    }
    final frames = <GlassProxyFrame?>[];
    for (var level = 1; level <= levels.top; level++) {
      final _Level selected = levels.select(level, present, rects, finishes, _finish);
      while (_upperPipelines.length < level) {
        _upperPipelines.add(_newPipeline());
      }
      frames.add(
        _upperPipelines[level - 1].capture(
          root,
          selected.rects,
          devicePixelRatio: dpr,
          keys: selected.keys,
          fused: _fusedGrouping(selected.keys),
          finishes: selected.mixed ? selected.finishes : null,
          glass: (RenderObject child) => levels.policy(child, level),
        ),
      );
      // Before the next level's walk, which draws this one.
      _handle.publishUpper(frames);
    }
    _publishUpper(frames, previous: previous);
  }

  /// Publishes [frames] as the upper levels and disposes whatever they
  /// replaced — after, so that no surface is ever left pointing at a released
  /// texture between the two.
  void _publishUpper(List<GlassProxyFrame?> frames, {List<GlassProxyFrame?>? previous}) {
    final List<GlassProxyFrame?> old = previous ?? _handle.upper;
    _handle.publishUpper(frames);
    for (final GlassProxyFrame? frame in old) {
      if (frame != null && !frames.contains(frame)) {
        frame.dispose();
      }
    }
    if (frames.isEmpty) {
      for (final GlassProxyPipeline pipeline in _upperPipelines) {
        pipeline.dispose();
      }
      _upperPipelines.clear();
    }
  }

  final List<GlassProxyPipeline> _upperPipelines = <GlassProxyPipeline>[];

  List<double>? _lastBlurs;

  void _readCounters() {
    var snapshots = _pipeline.snapshots;
    for (final GlassProxyPipeline pipeline in _upperPipelines) {
      snapshots += pipeline.snapshots;
    }
    _handle.snapshots = snapshots;
    _handle.repacks = _pipeline.repacks;
    _handle.ceilingDeepenings = _pipeline.ceilingDeepenings;
    _handle.ceilingRefusals = _pipeline.ceilingRefusals;
    _handle.ceilingOverruns = _pipeline.ceilingOverruns;
  }

  /// The blend groups, as indices into [present].
  ///
  /// The one-way invariant of §4.4 said in the only place it can be enforced:
  /// the packer is *given* these and may merge them with anything, but cannot
  /// take one apart. Asserting it after the fact would be a check on a layout
  /// that had already been recorded.
  ///
  /// A member that could not say where it is has no index and drops out, which
  /// leaves a group of one — the same shape as a group whose second surface has
  /// not mounted yet, and the fused draw handles it because a fold of one smooth
  /// minimum is the shape itself.
  List<List<int>>? _fusedGrouping(List<GlassSurfaceGeometry> present) {
    if (_ledger.clusters.isEmpty) {
      return null;
    }
    final index = <Object, int>{for (var i = 0; i < present.length; i++) present[i]: i};
    final out = <List<int>>[];
    for (final GlassSurfaceCluster cluster in _ledger.clusters) {
      final members = <int>[
        for (final GlassSurfaceGeometry surface in cluster.members)
          if (index[surface] case final int i) i,
      ];
      if (members.length > 1) {
        out.add(members..sort());
      }
    }
    return out.isEmpty ? null : out;
  }

  /// The framework repainted the screen under the glass, so its pixels changed.
  ///
  /// This was the mechanism for one day (D150) and is now the *control* on the
  /// mechanism, which is the only reason it survives. `ProxyLayerWatch` sees
  /// everything this sees and a great deal more — deleting this observation
  /// entirely fails no arm anywhere, which is how its redundancy was
  /// established rather than argued — but the implication runs one way and is
  /// exact: the framework cannot paint this subtree without minting a new
  /// `ui.Picture` in the layer that owns it, so "painted, and the watch saw
  /// nothing" is a hole in the watch's table and nothing else. Asserted every
  /// frame of every debug run of every application, which is a great many more
  /// screens than this repository will ever hold.
  ///
  /// It still reports the change in profile, where the assert is stripped. That
  /// costs nothing (the watch is consulted either way) and errs towards
  /// recording, which is the safe direction: a capture nobody needed is
  /// expensive, a change nobody noticed is a visibly wrong picture.
  void _noteRepaint() {
    _framePainted = true;
    _oracle.noteChange();
  }

  /// Ask the composited output whether anything under the host moved.
  ///
  /// The one input that has no blind spot, and the reason a declaration can be
  /// a *permission* rather than a promise: the application says the glass may
  /// hold, and this establishes whether it should. Errs towards recording in
  /// every direction it can — no layer yet, a layer type the table does not
  /// know, a texture whose pixels arrive from outside Dart.
  void _noteCompositedChanges(
    RenderObject root,
    List<GlassSurfaceGeometry> surfaces,
    _Levels levels,
  ) {
    // `layer` rather than `debugLayer`, for the reason `ProxyRecorder.stock`
    // gives: the second is wrapped in an assert and is null in profile.
    // ignore: invalid_use_of_protected_member
    final ContainerLayer? rootLayer = root is RenderRepaintBoundary ? root.layer : null;
    if (rootLayer == null) {
      _oracle.noteChange();
      return;
    }
    final exclude = <Layer>{};
    for (final GlassSurfaceGeometry surface in surfaces) {
      // `excludedFromProxy` rather than "it is a surface", because those two
      // parted company when the ladder did: a surface below the top rung is in
      // the proxy, so a change inside it has to invalidate the proxy like any
      // other content. Excluding it would hold a backdrop over a panel that had
      // moved — and the same predicate is what keeps it in the walk, which is
      // why it is read from there rather than recomputed here.
      //
      // And only the draw when glass stands on this surface: its subtree is
      // then in the proxy of the level above — the bar's icons under the lens —
      // so a change there invalidates it like any other content, while the
      // draw itself is replaced by every publish and would record for ever.
      final Layer? layer = !surface.excludedFromProxy
          ? null
          : levels.bears(surface)
          ? surface.drawLayer
          : surface.compositedLayer;
      if (layer != null) {
        exclude.add(layer);
      }
    }
    // And the blend groups, which draw glass of their own. Their members' layers
    // are inside theirs and go with them; the walk skips that whole subtree, so
    // nothing inside it is in the proxy to be invalidated.
    for (final GlassSurfaceCluster cluster in _ledger.clusters) {
      final Layer? layer = !cluster.excludedFromProxy
          ? null
          : cluster.members.any(levels.bears)
          ? cluster.drawLayer
          : cluster.compositedLayer;
      if (layer != null) {
        exclude.add(layer);
      }
    }
    final LayerChange change = _watch.changeSince(rootLayer, exclude: exclude);
    _handle.watchedLayers = _watch.lastLength;
    assert(() {
      // Advanced on every call, painted or not, so its previous frame is the
      // oracle's walk's previous frame.
      final LayerChange content = _debugWatchContent.changeSince(
        rootLayer,
        exclude: <Layer>{
          for (final GlassSurfaceGeometry surface in surfaces) ?surface.drawLayer,
          for (final GlassSurfaceCluster cluster in _ledger.clusters) ?cluster.drawLayer,
        },
      );
      if (_framePainted && !content.changed && _debugRepaintMintedPicture(root, rootLayer)) {
        throw FlutterError(
          'GlassHost: the framework painted the screen under this host and the '
          'layer watch reported no change, glass content included. A repaint mints a new '
          'ui.Picture in the layer that owns it, so this is a hole in '
          'ProxyLayerWatch, not a still screen. The proxy would have been held '
          'over changed pixels.',
        );
      }
      return true;
    }());
    if (!change.changed) {
      return;
    }
    // §4.2, asked of the one thing that can answer it exactly: the proxy holds
    // the inside of the slots and nothing else, so a change that misses every
    // source rect has missed every texel of the atlas. It is still a change —
    // the assertion above is about that, and folding the region into it would
    // turn a hole in the watch's table into a silent hold whenever the hole
    // happened to sit away from the glass.
    if (!_pipeline.capturedAreaTouchedBy(change) &&
        !_upperPipelines.any((GlassProxyPipeline p) => p.capturedAreaTouchedBy(change))) {
      _handle.changesOutsideCapture++;
      return;
    }
    _oracle.noteChange();
  }

  /// Whether the host's boundary, repainted this frame, drew anything of its
  /// own — a picture under its layer that no nested repaint boundary owns.
  ///
  /// The premise of the watch's assertion is "a repaint mints a picture", and it
  /// is false for a boundary that draws nothing itself. `RenderObject.layout`
  /// marks paint unconditionally (`object.dart:2939`), so a relayout that lands
  /// on the same geometry — an application's `setState` above a `Scaffold`
  /// re-running its layout — repaints the host's boundary, and when every pixel
  /// under it belongs to a nested boundary (list items, a control's track, the
  /// glass) the repaint re-appends retained layers and mints nothing. The
  /// screen is still, the watch is right, and the example application's slider
  /// tripped the assertion on its first press.
  ///
  /// A picture outside every nested boundary is one this repaint recorded
  /// afresh, so with one present a silent watch is still a hole. Debug only,
  /// and asked only on the frame the assertion would otherwise fire.
  bool _debugRepaintMintedPicture(RenderObject root, ContainerLayer rootLayer) {
    final owned = <Layer>{};
    void boundaries(RenderObject node) {
      node.visitChildren((RenderObject child) {
        // ignore: invalid_use_of_protected_member
        final Layer? layer = child.isRepaintBoundary ? child.layer : null;
        if (layer != null) {
          owned.add(layer);
        } else {
          boundaries(child);
        }
      });
    }

    boundaries(root);
    bool draws(Layer layer) {
      if (owned.contains(layer)) {
        return false;
      }
      if (layer is PictureLayer) {
        return true;
      }
      if (layer is ContainerLayer) {
        for (Layer? child = layer.firstChild; child != null; child = child.nextSibling) {
          if (draws(child)) {
            return true;
          }
        }
      }
      return false;
    }

    return draws(rootLayer);
  }

  @override
  Widget build(BuildContext context) {
    // Every frame: the oracle decides whether anything is actually recorded, so
    // this is a scheduling question rather than a cost one.
    _scheduleCapture();
    return GlassScope(
      ledger: _ledger,
      child: GlassTheme(
        // The host installs the theme rather than reading one, so that the
        // finish has exactly one home. It used to travel on `GlassProxyHandle`,
        // which is the pipeline — and a surface below the top rung has no
        // pipeline, so a cheap panel with no host above it would have had no
        // finish to draw.
        data: GlassThemeData(
          finish: _finish,
          tier: widget.tier,
          backdrop: widget.backdrop,
          highContrast: widget.highContrast ?? MediaQuery.maybeHighContrastOf(context) ?? false,
          richBackdrop: widget.richBackdrop,
          minLabelContrast: widget.minLabelContrast,
          ripple: widget.ripple,
        ),
        child: GlassProxyScope(
          handle: _handle,
          child: RepaintBoundary(
            key: _rootKey,
            // Inside the boundary rather than outside it: what is being
            // observed is that *this* boundary repainted, and a node above it
            // is painted by whatever encloses the host instead.
            child: _GlassRepaintObserver(onRepaint: _noteRepaint, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Reports that the framework painted the host's subtree.
///
/// Transparent to layout and hit testing — it is a `RenderProxyBox` and nothing
/// else — and its whole content is one call per repaint of the host's boundary.
class _GlassRepaintObserver extends SingleChildRenderObjectWidget {
  const _GlassRepaintObserver({required this.onRepaint, required Widget super.child});

  final VoidCallback onRepaint;

  @override
  _RenderGlassRepaintObserver createRenderObject(BuildContext context) => _RenderGlassRepaintObserver(onRepaint);

  @override
  void updateRenderObject(BuildContext context, _RenderGlassRepaintObserver renderObject) {
    renderObject.onRepaint = onRepaint;
  }
}

class _RenderGlassRepaintObserver extends RenderProxyBox {
  _RenderGlassRepaintObserver(this.onRepaint);

  VoidCallback onRepaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    // The capture pass paints this same subtree through its own context every
    // time it records. Counting that would declare a change on the frame after
    // every capture — a loop that records for ever and holds nothing — and the
    // arm that catches it is a still screen, which must still be held.
    if (context is! ProxyWalkContext) {
      onRepaint();
    }
    super.paint(context, offset);
  }
}

/// Which glass stands on which: each surface's level is the number of glass
/// surfaces above it in the tree that are themselves being captured.
///
/// The tree rather than the screen, on purpose. Overlap is not the question —
/// two sibling panels that overlap are two panels of one level, each over the
/// same backdrop — and a lens that should refract the bar under it is written
/// *inside* the bar, which is where its paint order puts it on top anyway.
/// Counting only surfaces that are captured is what keeps a drop at rest
/// (presence zero, no draw) from lifting what stands on it a level for nothing.
class _Levels {
  _Levels._(this._of, this._bearing, this.top);

  factory _Levels.of(List<GlassSurfaceGeometry> present, RenderObject root) {
    final Set<Object> captured = present.toSet();
    final of = <Object, int>{};
    final bearing = <Object>{};
    var lifted = false;
    for (final GlassSurfaceGeometry surface in present) {
      var level = 0;
      if (surface is RenderObject) {
        var inside = 0;
        for (
          RenderObject? node = (surface as RenderObject).parent;
          node != null && !identical(node, root);
          node = node.parent
        ) {
          if (captured.contains(node)) {
            if (inside == 0) {
              bearing.add(node);
            }
            inside++;
            level++;
          } else if (node is RenderGlassAbove) {
            level += node.lift;
            lifted = true;
          }
        }
      }
      of[surface] = level;
    }
    // Numbered by occupancy, so a level is a snapshot only when it has glass
    // under it: a lifted bar over plain content is level 0, captured with
    // everything else, and lifts of 1 and 3 over a page are two levels, not
    // four. The tree's levels are dense already — a glass inside a captured
    // glass is one above it — so this changes nothing on a screen with no
    // [GlassAbove].
    final List<int> occupied = of.values.toSet().toList()..sort();
    final rank = <int, int>{for (var i = 0; i < occupied.length; i++) occupied[i]: i};
    for (final Object surface in of.keys) {
      of[surface] = rank[of[surface]]!;
    }
    var top = 0;
    for (final int level in of.values) {
      if (level > top) {
        top = level;
      }
    }
    // Under a lift, what bears glass is not something the tree says — the
    // cards under a lifted bar are its siblings — so every surface below the
    // top bears: its draw is excluded from the watch and its subtree is
    // watched, because that subtree is in the capture of the level above.
    // Conservative where the lifted glass covers none of them, and the watch
    // is screen-wide anyway: a change in a card retakes either way.
    if (lifted && top > 0) {
      for (final MapEntry<Object, int> entry in of.entries) {
        if (entry.value < top) {
          bearing.add(entry.key);
        }
      }
    }
    return _Levels._(of, bearing, top);
  }

  final Map<Object, int> _of;
  final Set<Object> _bearing;

  /// The highest level present; zero on a screen with no glass on glass.
  final int top;

  /// Whether some captured glass stands directly on [surface].
  bool bears(Object surface) => _bearing.contains(surface);

  /// The surfaces of [level], in register order.
  _Level select(
    int level,
    List<GlassSurfaceGeometry> present,
    List<Rect> rects,
    List<GlassFinish> finishes,
    GlassFinish host,
  ) {
    if (top == 0) {
      return _Level(present, rects, finishes, host);
    }
    final keys = <GlassSurfaceGeometry>[];
    final out = <Rect>[];
    final worn = <GlassFinish>[];
    for (var i = 0; i < present.length; i++) {
      if (_of[present[i]] == level) {
        keys.add(present[i]);
        out.add(rects[i]);
        worn.add(finishes[i]);
      }
    }
    return _Level(keys, out, worn, host);
  }

  /// The walk of [level]: glass below it is drawn, its own and above skipped.
  ///
  /// A group is at its members' level — fused members share a silhouette, so
  /// they share a level by construction. Glass the register did not capture
  /// (presence zero) is skipped at every level, as it always was.
  WalkAction policy(RenderObject child, int level) {
    if (child is RenderGlassSurface && child.excludedFromProxy) {
      final int? at = _of[child];
      return at != null && at < level ? WalkAction.paint : WalkAction.skip;
    }
    if (child is RenderGlassGroup && child.group.excludedFromProxy) {
      int? at;
      for (final GlassSurfaceGeometry member in child.group.members) {
        at ??= _of[member];
      }
      return at != null && at < level ? WalkAction.paint : WalkAction.skip;
    }
    return skipGlassSurfaces(child);
  }
}

class _Level {
  _Level(this.keys, this.rects, this.finishes, GlassFinish host)
    : mixed = finishes.any(
        (GlassFinish f) => f.name != host.name || f.blurSigmaLogical != host.blurSigmaLogical,
      );

  final List<GlassSurfaceGeometry> keys;
  final List<Rect> rects;
  final List<GlassFinish> finishes;
  final bool mixed;
}
