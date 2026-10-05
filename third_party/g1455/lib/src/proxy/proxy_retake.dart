// When to re-record the proxy — the last piece of the skeleton, and the one
// whose answer is uncomfortable.
//
// The roadmap's shape for it is "re-take on a dirty rect from the D2 oracle,
// with a threshold and a frequency ceiling", and it says the ceiling is
// assigned by the finish rather than by taste, because a frame of staleness has
// a measured price. It has. The price is higher than the shape assumed.
//
// **A frame behind costs at least what a quarter of the resolution does**, on
// every finish the ladder has run (mean over the seven corpus scenes, ΔE
// against the same finish at full quality) — 1.17x on `clear`, 1.77x on
// `thinLight`, 1.73x on `regular`, and 0.98x on `frosted`, which is the one
// place the two are equal:
//
// | finish | 1 frame | 2 frames | 4 frames | for contrast: a quarter of the resolution |
// |---|---|---|---|---|
// | `clear` | 1.496 | 2.474 | 3.812 | 1.279 |
// | `thinLight` | 0.795 | 1.489 | 2.646 | 0.449 |
// | `frosted` | 0.488 | 0.830 | 1.448 | 0.500 |
// | `regular` | 0.384 | 0.675 | 1.150 | 0.222 |
//
// That `frosted` sits level and the others do not is the shape of the thing: a
// blur is a low-pass in space, and what it hides is lost detail rather than a
// picture from a moment ago. The heavier the blur, the more of the resolution's
// damage it takes away — and none of the staleness.
//
// So at the budget that picks a quarter-resolution proxy — 1% of the distance
// between two of Apple's own materials, 0.348 ΔE — **no finish may be stale at
// all**. The ceiling is zero frames, and the lever the roadmap expected to find
// here is not there. What is left is the other half, which is worth more: a
// proxy is only stale if something *moved*, and the ladder's latency rungs are
// a scene that moves every frame at full speed. Retake when the scene changes,
// and the ceiling is a backstop rather than a schedule.
//
// ⚠️ The numbers above are today's optics. D30 quotes 0.43 / 0.80 / 1.51 behind
// sigma 8, which is the same ladder before M13 recalibrated the shader; the two
// are close and they are not the same, and the second one is the one this
// package renders.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../thermal.dart';
import 'proxy_resolution.dart';
import 'proxy_role.dart';

/// How damage on several axes adds up — measured, and not the way a budget
/// would like.
abstract final class GlassDamage {
  /// Composes per-axis damage into the damage of doing all of it at once.
  ///
  /// **The sum is refuted.** Over 56 cells — two combination rungs of the M11
  /// ladder, seven scenes, four finishes — adding the parts overstates the
  /// measured combination by a median of **38%** and by up to 147%. Two models
  /// survive and they bracket the truth: the largest part alone is the better
  /// description (median bias −0.7%, median error 4.1%) and the quadrature is
  /// the safer one (+3.5%, 6.8%).
  ///
  /// This returns the quadrature, for two reasons that agree. A budget wants
  /// the conservative side of a pair that brackets, and the same rule already
  /// governs the *sigmas* these damages come from: a divisor's low-pass and a
  /// finish's blur compose in quadrature (D117), so their damages composing the
  /// same way is one rule rather than two.
  ///
  /// The measurement needed a rung built for it. The ladder's own `mix` is
  /// three parts of which one is four to seven times the others, so every model
  /// predicts nearly the same number there; `res8lag2` puts resolution and
  /// staleness within a factor of two on every finish, which is what let the
  /// models separate (40% against 7%).
  static double compose(Iterable<double> parts) {
    var sum = 0.0;
    for (final double part in parts) {
      sum += part * part;
    }
    return math.sqrt(sum);
  }

  /// What is left of [budget] once [spent] has been spent on another axis.
  ///
  /// The inverse of [compose], and the reason the axes cannot be budgeted
  /// separately: a proxy already recorded at a quarter has spent part of the
  /// same allowance the staleness would draw on.
  static double remaining(double budget, double spent) => math.sqrt(math.max(0, budget * budget - spent * spent));
}

/// What a frame of staleness costs, per finish.
abstract final class ProxyStaleness {
  /// The report these came from — the same ladder the resolution damage is read
  /// from, and tracked for the same reason.
  static const String source = 'provenance/quality/d117-uncorrected-2026-09-08T06-39-52.json';

  /// The rung that made the composition rule measurable, on the run that took
  /// it. Its parts are `res8` and `lag2`, chosen to be within a factor of two.
  static const String compositionSource = 'provenance/quality/d124-compose';

  /// Mean ΔE against the same finish at full quality, by frames behind.
  ///
  /// Read as damage relative to *that* finish, never as an absolute: a more
  /// opaque finish is more forgiving by construction, which is why `regularDark`
  /// tolerates four frames for what `clear` pays for one.
  static const Map<String, Map<int, double>> _damage = <String, Map<int, double>>{
    'clear': <int, double>{0: 0.0, 1: 1.496, 2: 2.474, 4: 3.812},
    'thinLight': <int, double>{0: 0.0, 1: 0.795, 2: 1.489, 4: 2.646},
    'frosted': <int, double>{0: 0.0, 1: 0.488, 2: 0.830, 4: 1.448},
    'regularDark': <int, double>{0: 0.0, 1: 0.384, 2: 0.675, 4: 1.150},
    // From [ProxyResolution.lightDamageSource], whose `regular` lag arms
    // reproduce these to the third decimal.
    'regularLight': <int, double>{0: 0.0, 1: 0.284, 2: 0.493, 4: 0.831},
  };

  /// Damage at a measured number of frames behind, or null for a point the
  /// ladder never ran.
  ///
  /// Refuses rather than interpolating: the rungs are 1, 2 and 4, three is not
  /// among them, and the curve's shape between them is nobody's measurement.
  static double? damageAt(String finish, int framesBehind) => _damage[finish]?[framesBehind];

  /// The most frames a proxy of [finish] may be behind before it costs more
  /// than [budgetDeltaE].
  ///
  /// Zero is the common answer and it is the finding rather than a degenerate
  /// case: at the default budget every finish's first stale frame is already
  /// over. A caller who wants a ceiling above zero is choosing to spend more
  /// than 1% of the material scale on staleness, which is a decision and should
  /// look like one.
  static int maxStaleFrames(String finish, double budgetDeltaE) {
    final Map<int, double>? table = _damage[finish];
    if (table == null) {
      return 0;
    }
    var best = 0;
    for (final MapEntry<int, double> rung in table.entries) {
      if (rung.value <= budgetDeltaE && rung.key > best) {
        best = rung.key;
      }
    }
    return best;
  }

  static const List<String> measuredFinishes = <String>[
    'clear',
    'thinLight',
    'frosted',
    'regularDark',
    'regularLight',
  ];
}

/// What the retake may spend on staleness under thermal pressure — the
/// thermal lever, and a policy rather than a panic.
///
/// **Thermals act on the retake, not on the ladder** (`glass_tier.dart`). A
/// frame of staleness has a measured price per finish ([ProxyStaleness]): 0.384
/// ΔE behind `regular`, 0.488 behind `frosted`, 1.496 behind `clear`. So the
/// same allowance buys a heavy finish frames and a clear one none, which is the
/// sentence the roadmap wrote before the table existed — throttling under a
/// matte finish is nearly free and under a transparent one it is forbidden —
/// now as arithmetic instead of advice (D205).
///
/// What a throttle does: when the screen *under* the glass changes, the proxy
/// may be up to [throttleFrames] frames old before it is re-recorded, so a
/// scroll captures every `n + 1`th frame instead of every frame. It never holds
/// across a change of the surfaces themselves — a panel that moved or resized
/// is reading a different part of the screen, which is not a stale picture but
/// a wrong one — and never before the first capture.
///
/// The allowances are **the package's choice, in the project's own unit**: 2%
/// and 4% of the distance between Apple's `.regular` and `.clear` (S4) for
/// [GlassThermalState.serious] and [GlassThermalState.critical], against the 1%
/// the resolution policy spends on an ordinary frame. Nothing at
/// [GlassThermalState.fair], where both platforms say the user notices
/// nothing. They are allowances rather than measurements and named as such;
/// what *is* measured is what each buys:
///
/// | finish | serious (0.696 ΔE) | critical (1.392 ΔE) |
/// |---|---|---|
/// | `regular` | 2 frames | 4 frames |
/// | `frosted` | 1 frame | 2 frames |
/// | `thinLight` | 0 | 1 frame |
/// | `clear` | 0 | 0 |
///
/// — before whatever the resolution already spent, which comes off first in
/// quadrature (D124), so a screen at a coarse divisor gets fewer.
@immutable
class GlassThermalPolicy {
  const GlassThermalPolicy({
    this.fairDeltaE = 0,
    this.seriousDeltaE = 0.02 * ProxyResolution.kMaterialScaleDeltaE,
    this.criticalDeltaE = 0.04 * ProxyResolution.kMaterialScaleDeltaE,
  });

  /// No throttle at any state: what a host that wants every frame fresh passes.
  static const GlassThermalPolicy never = GlassThermalPolicy(
    seriousDeltaE: 0,
    criticalDeltaE: 0,
  );

  final double fairDeltaE;
  final double seriousDeltaE;
  final double criticalDeltaE;

  /// The whole quality allowance at [state], or zero — no raise at all — for
  /// [GlassThermalState.nominal] and for an unknown state.
  ///
  /// Unknown is nominal here and not a guess in either direction: a throttle is
  /// a visible loss, and a package that took one on a device that never said it
  /// was hot would be spending the application's picture on nothing.
  double allowanceFor(GlassThermalState? state) => switch (state) {
    null || GlassThermalState.nominal => 0,
    GlassThermalState.fair => fairDeltaE,
    GlassThermalState.serious => seriousDeltaE,
    GlassThermalState.critical => criticalDeltaE,
  };

  /// How many frames a proxy of [finish] may lag a changing screen at [state],
  /// once [spentDeltaE] has gone on the resolution.
  int throttleFrames(String finish, GlassThermalState? state, {double spentDeltaE = 0}) {
    final double allowance = allowanceFor(state);
    if (allowance <= 0) {
      return 0;
    }
    return ProxyStaleness.maxStaleFrames(finish, GlassDamage.remaining(allowance, spentDeltaE));
  }

  @override
  bool operator ==(Object other) =>
      other is GlassThermalPolicy &&
      other.fairDeltaE == fairDeltaE &&
      other.seriousDeltaE == seriousDeltaE &&
      other.criticalDeltaE == criticalDeltaE;

  @override
  int get hashCode => Object.hash(fairDeltaE, seriousDeltaE, criticalDeltaE);
}

/// Whether the host may hold a proxy that nothing it watches has changed.
///
/// It began as the sixth thing on the same list as occlusion (D42), reduced
/// transparency (D59), the roles (D115), the hardware (D121) and the shadow
/// policy — something the package cannot work out, so whoever can says it — and
/// it has stopped being that. Since D152 nothing about *content* is declared
/// here at all: `ProxyLayerWatch` reads the host's composited subtree, and what
/// is left in this enum is a permission to use that answer.
///
/// **Why it exists at all.** [RetakeOracle.ceiling] is zero on every measured
/// finish at the default budget, so before this enum the `hold` branch was
/// unreachable and the proxy was re-recorded on every frame of every
/// application, a completely still screen included (D142). That zero is not a
/// defect in the staleness table — the table is about a **moving** scene, and
/// the branch it gates has just established that nothing the oracle can see
/// changed, where staleness of unchanged content costs zero rather than 0.384.
/// The ceiling is a hedge against changes the oracle cannot see.
///
/// **Which side is the default moved on 2026-09-12 (D163), and it took three
/// findings to move it.** The old default was [undeclared], on the reasoning
/// that a held proxy over changed content is wrong where a re-recorded proxy
/// over still content is merely expensive. Both halves of that reasoning are
/// now measured rather than assumed. What it costs: 79.4% and 66.3% of the
/// addition on Adreno and 97.8% on Metal (D146), which is most of the price of
/// the whole route, paid by every application on every still frame. What it
/// buys: coverage of changes the oracle cannot see — and since D152 the oracle
/// sees the composited output, where a repaint cannot hide, so the remaining
/// exposure is a hole in one table of layer types. That table was audited
/// against `layer.dart` in D162, the one hole in it was closed, and it is now
/// checked against the SDK in a test rather than by reading. What the walk
/// costs: under 3 µs a frame, below what a device run can resolve (D160).
enum GlassContentDeclaration {
  /// Assume anything may have changed since the last frame, and re-record.
  ///
  /// No longer the default, and what it now means is "distrust the watch":
  /// the proxy is re-recorded on every frame regardless of what the composited
  /// subtree says. It is the most expensive thing this package can be asked to
  /// do — the capture is 77% of what the route adds at the divisor the policy
  /// picks on a dpr-2 screen (D141) — and it is worth asking for in exactly two
  /// situations: a host that composites through a layer type it has reason to
  /// think this package misreads, and an arm of a benchmark that wants the
  /// capture measured on every frame.
  undeclared,

  /// Hold a clean proxy, and let the watch decide what "clean" means.
  ///
  /// **The default since D163.** Under it a clean proxy is held
  /// **indefinitely**: the ceiling is not consulted at all, because a picture
  /// that did not change costs nothing to be a frame old, and consulting a
  /// table measured on a moving scene would return zero and undo the whole
  /// thing.
  ///
  /// **This is a permission and not a promise, since D152.** For one day it was
  /// a promise, and the census that established what the application would have
  /// to keep also measured how often: a realistic screen crosses 8 to 15 nested
  /// repaint boundaries, and every one of them was a clause nobody could verify.
  /// What decides now is `ProxyLayerWatch`, which reads the host's composited
  /// subtree rather than its render tree — a repaint cannot hide from the layer
  /// that owns it, and the one change that repaints nothing is a property of a
  /// retained layer.
  ///
  /// **What is left for the application to say is nothing about its content.**
  /// The one input that is still a declaration is what a [GlassProxy] marker
  /// says, and that is not about pixels: a marker changing role changes what the
  /// *capture* would draw while the screen stays exactly as it was.
  /// [GlassProxyHandle.noteChange] remains as the imperative override for
  /// anything an application knows and the composited output does not.
  ///
  /// What the host still cannot see, it refuses to hold through rather than
  /// believing anybody: a `Texture`, a platform view and any layer type the
  /// watch's table has never met read as changing on every frame. That refusal
  /// is what makes this a safe default rather than an optimistic one, and it is
  /// why the table it stands on is checked against the SDK's own `layer.dart`
  /// (D162) instead of against the scenes in this repository.
  ///
  /// **Since D174 the watch says *where*, and the hold no longer needs the
  /// screen to be still — only the glass to be missed.** `ProxyLayerWatch`
  /// returns a region, and the host compares it against what the atlas actually
  /// holds; a change that reaches no slot is held through. On a screen with one
  /// spinner turning 500 logical pixels from a glass bar, that is **one capture
  /// in a 30-second window** against one per frame, and the glass arm is
  /// **6.5-10.2% cheaper** for it. The same spinner moved *inside* the bar
  /// captures on every frame and the two arms then agree to 0.6% — which is the
  /// control that says the saving belongs to the placement rather than to the
  /// scene being cheap.
  ///
  /// ⚠️ **As a share of what the route adds, it is a range and not a number:**
  /// two seeds say 94% and 56%, because that share is a small difference of
  /// large numbers and the per-arm spread on the device it was taken on runs to
  /// 12.6%. What both seeds and both instruments agree on is that the declared
  /// arm sits on the floor — indistinguishable from the same screen with no
  /// glass in it (`provenance/digest/s22u-aside-{a,b}.json`, Xclipse 920,
  /// one device).
  ///
  /// The bound is never tighter than the nearest enclosing repaint boundary —
  /// `PictureLayer.canvasBounds` is the boundary's bounds and not the picture's
  /// — so this pays where the change sits in a nested boundary that misses the
  /// glass, and not otherwise. How common that is, is a property of the
  /// application's tree: every scene in this repository's own corpus changes
  /// what is under its glass on every frame, by construction.
  declared;

  /// What a host uses when the application says nothing.
  ///
  /// Named rather than spelled out, because two places outside `lib/` have to
  /// mount *the default* and not a copy of today's value: the playground's
  /// fallback and the bench's record of what ran. A copied literal in either is
  /// a run whose default arm measures the arm nobody ships — which is the
  /// defect D147 cost a day to, in the other direction.
  static const GlassContentDeclaration byDefault = declared;
}

/// Why the oracle decided what it decided.
enum RetakeReason {
  /// There is no proxy yet.
  first,

  /// Something the oracle can see has changed: a surface moved or resized, or a
  /// [GlassProxy] marker's contribution changed.
  changed,

  /// Nothing visibly changed, and the proxy has been held for as long as the
  /// finish's own tolerance allows.
  ceiling,

  /// Nothing changed and the ceiling has not been reached.
  hold,

  /// The screen under the glass changed, and the proxy is held anyway because
  /// thermal pressure bought it frames of staleness ([GlassThermalPolicy]).
  ///
  /// A reason of its own because it is the one hold that knows the proxy is
  /// out of date: [hold] and [declared] keep a picture that is still right.
  throttled,

  /// Nothing changed, and the host declared that nothing can change unseen.
  ///
  /// Separate from [hold] rather than folded into it because the two are held
  /// for opposite reasons — one is inside a measured budget, the other is
  /// outside it by declaration — and a report that could not tell them apart
  /// would be unreadable the moment a host raises [RetakeOracle.budgetDeltaE].
  declared;

  /// Whether this decision keeps the proxy that is already there.
  bool get holds => this == RetakeReason.hold || this == RetakeReason.declared || this == RetakeReason.throttled;
}

/// Decides when the proxy is re-recorded.
///
/// Two inputs and neither is a guess. **What changed** is observed where it can
/// be — the surfaces' own geometry, and every [GlassProxy] marker in the
/// subtree, which is what `proxyChanges` has been publishing since D115 with
/// nobody listening — and *declared* where it cannot.
///
/// Where the line falls turned out to be a property of *which tree is being
/// watched*. Nothing in the render tree reports that a subtree repainted, and
/// every observation built on it stops at a nested repaint boundary — of which a
/// realistic screen has 8 to 15. The composited tree cannot stay silent about
/// the same events, because it is what was shown, so since D152 the host asks it
/// once per frame and reports the answer here through [noteChange] like anything
/// else. What genuinely remains a declaration is not about content at all: it is
/// what a [GlassProxy] marker says, which changes the *capture* rather than the
/// screen. That is the same list as occlusion (D42), reduced transparency (D59),
/// the roles (D115) and the hardware (D121).
///
/// **How long it may be held** is the measured half, and it is [ProxyStaleness].
class RetakeOracle {
  RetakeOracle({
    required this.finish,
    this.budgetDeltaE = ProxyResolutionPolicy.defaultDamageBudgetDeltaE,
    this.content = GlassContentDeclaration.byDefault,
  });
  // There was a `spentDeltaE` parameter here, and it never had a caller: what
  // the resolution spends is a function of the screen's density and so is not
  // known when the host builds the oracle. That is why it is [noteResolutionDamage]
  // now — a constructor argument nobody can supply is a budget nobody shares.

  /// Key into the measured staleness table.
  final String finish;

  /// The whole quality allowance, in ΔE against the same finish at full
  /// quality. The default is 1% of the distance between `Glass.regular` and
  /// `Glass.clear` (S4) — literally the resolution policy's own constant, and
  /// deliberately so: the two axes draw on one budget.
  final double budgetDeltaE;

  /// What the host says about content that changes without moving a surface.
  ///
  /// The only lever the capture has — not taking it — and it is switched off by
  /// arithmetic unless the host turns it on (D142). See
  /// [GlassContentDeclaration].
  final GlassContentDeclaration content;

  double _spentDeltaE = 0;

  /// What another axis has already spent out of [budgetDeltaE].
  ///
  /// In practice the proxy's resolution, and it is not known when this is
  /// built: the divisor is a function of the screen's density, which arrives
  /// with the first frame. So it is *noted* rather than passed, and the ceiling
  /// follows it.
  double get spentDeltaE => _spentDeltaE;

  /// Notes what the resolution policy spent, so the ceiling is what is left
  /// rather than the whole allowance.
  ///
  /// D124: damage on two axes does not add — the composition is between the
  /// largest part and the quadrature, and the quadrature is the safe side — so
  /// what staleness may spend is `sqrt(budget² − spent²)`. Without this the
  /// package charged the *same* allowance to both axes, which is the one model
  /// the measurement rules out.
  void noteResolutionDamage(double deltaE) => _spentDeltaE = deltaE;

  /// The most frames this proxy may be held when nothing has changed.
  ///
  /// Zero at the default budget for every measured finish, whatever the
  /// resolution spent — which is why wiring [noteResolutionDamage] changes no
  /// default behaviour and is still the difference between a budget that is
  /// shared and one that is spent twice.
  int get ceiling => ProxyStaleness.maxStaleFrames(
    finish,
    GlassDamage.remaining(budgetDeltaE, _spentDeltaE),
  );

  bool _dirty = true;

  /// Whether the *surfaces* changed, as opposed to what is under them. Kept
  /// apart because a throttle may hold across the second and never the first.
  bool _geometryDirty = true;
  int _framesSinceCapture = 0;

  /// How many frames the proxy may lag a changing screen before it is
  /// re-recorded. Zero — no throttle — unless the host has a thermal state and
  /// a policy that spends on it ([GlassThermalPolicy.throttleFrames]).
  ///
  /// Set rather than constructed, because the state arrives while the screen
  /// runs and rebuilding the oracle would forget what it was watching.
  int throttleFrames = 0;
  final List<Listenable> _watched = <Listenable>[];

  /// Whether something the oracle can see has changed since the last capture.
  bool get dirty => _dirty;

  int get framesSinceCapture => _framesSinceCapture;

  /// Declares a change the oracle cannot observe.
  ///
  /// The escape hatch that keeps this honest, and the one input the host's own
  /// observations arrive through as well: the layer watch's verdict, the host's
  /// own repaint and an application calling `GlassProxyHandle.noteChange` are
  /// the same event as far as this class is concerned. Since D152 the first of
  /// those subsumes the rest for anything that reaches a pixel, and what an
  /// application would still call this for is something it knows that the
  /// composited output does not show.
  void noteChange() => _dirty = true;

  /// Subscribes to every [GlassProxy] marker in the subtree.
  ///
  /// Idempotent per call: it drops what it was watching first. Call it when the
  /// tree's *structure* changes rather than every frame — the walk is
  /// `visitChildren` over the whole subtree, which is the cost M12 measured at
  /// 24 us per pass on this corpus, and paying it to discover that nothing
  /// changed is the opposite of the point.
  void watch(RenderObject root) {
    unwatch();
    void visit(RenderObject node) {
      if (node is RenderGlassProxy) {
        node.proxyChanges.addListener(noteChange);
        _watched.add(node.proxyChanges);
      }
      node.visitChildren(visit);
    }

    visit(root);
  }

  void unwatch() {
    for (final Listenable listenable in _watched) {
      listenable.removeListener(noteChange);
    }
    _watched.clear();
  }

  /// How many markers are being watched. Zero on a tree with no declarations,
  /// which is the common case and not an error.
  int get watchedMarkers => _watched.length;

  /// Notes this frame's surface geometry, which is a change the oracle *can*
  /// see: a surface that moved is looking at a different part of the screen.
  ///
  /// Compares against the geometry at the last capture rather than at the last
  /// frame, so a panel that drifts back to where it started does not force a
  /// retake it does not need.
  void noteSurfaces(List<Rect> surfaces) {
    if (_atCapture == null || _atCapture!.length != surfaces.length) {
      _dirty = true;
      _geometryDirty = true;
      return;
    }
    for (var i = 0; i < surfaces.length; i++) {
      if (_atCapture![i] != surfaces[i]) {
        _dirty = true;
        _geometryDirty = true;
        return;
      }
    }
  }

  List<Rect>? _atCapture;

  /// The decision for this frame.
  RetakeReason decide() {
    if (_atCapture == null) {
      return RetakeReason.first;
    }
    if (_dirty) {
      // Only the content, and only while the lag is inside what the throttle
      // bought: `framesSinceCapture` is how far behind the proxy already is.
      if (!_geometryDirty && _framesSinceCapture < throttleFrames) {
        return RetakeReason.throttled;
      }
      return RetakeReason.changed;
    }
    if (content == GlassContentDeclaration.declared) {
      // Deliberately before the ceiling and not after it: the ceiling is zero
      // on every measured finish at the default budget, so consulting it here
      // would return `ceiling` on the first held frame and the declaration
      // would buy nothing. What the table prices is a *moving* scene going
      // stale; this branch has established the scene did not move.
      return RetakeReason.declared;
    }
    return _framesSinceCapture >= ceiling ? RetakeReason.ceiling : RetakeReason.hold;
  }

  /// Whether [decide] says to record.
  bool get shouldRetake => !decide().holds;

  /// Called by whoever recorded, with the geometry that was recorded.
  void noteCapture(List<Rect> surfaces) {
    _atCapture = List<Rect>.of(surfaces);
    _dirty = false;
    _geometryDirty = false;
    _framesSinceCapture = 0;
  }

  /// Called once per frame that did not record.
  void noteFrame() => _framesSinceCapture++;

  void dispose() => unwatch();
}
