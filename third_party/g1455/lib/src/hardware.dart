// Whose measurements apply — the one thing the host declares that decides
// every cost answer this package gives.
//
// It exists because the two questions the package prices are priced on the same
// two devices and nowhere else, and their answers do not merely differ in a
// constant: the capture is charged by area on one and by the frame on the other
// (D28 against D56/D119, a factor of almost four on one knob), and the
// translucency tax is a linear law over a third of a screen on one and a flat
// stretch with a cliff at 19 screens on the other (D21/D26 against D71). Two
// enums name those model *shapes*, because that is the right vocabulary for
// each question; this names the *device family*, because that is what an
// application can actually know.
//
// **What the capture model does not answer is what the route costs**, and the
// distance between those two is 40% on Metal: the capture there is scale-free
// and the route is not, because the residual blur, the texture's bandwidth and
// the shader's sampling all pay by area (D128). The name below is
// [captureCostModel] because that is honestly what it is fitted from; the
// resolution policy reads it as evidence that a lever exists and then decides on
// quality, and the merge criterion — which really is a capture question — reads
// it as a price.
//
// **And it cannot be detected, which is the fourth time the same thing has
// happened.** `defaultTargetPlatform` separates Apple from everything else, and
// on Apple platforms Metal is the only backend Flutter ships — so that half is
// answerable. Android is not: the capture model was fitted on Adreno 830 and
// the same grid on Xclipse 920 returned `usable: false` on every fit, so
// "Android" is not an answer, and there is no API anywhere in Flutter that
// names the GPU. The one detector that would work is kgsl's own sysfs nodes,
// which the benchmark harness reads from inside the app — but this package has
// never measured that probe, so it does not ship it. The host declares instead,
// exactly as it declares occlusion (D42), reduced transparency (D59) and proxy
// roles (D115).

import 'package:flutter/foundation.dart';

import 'proxy/proxy_resolution.dart';
import 'surface/glass_ledger.dart';

/// The device family whose measurements apply.
///
/// One declaration, two questions. Declaring the wrong one is not a crash: it
/// makes the package quote a price that belongs to another device. The
/// *choices* — the proxy's divisor, whether slots merge — no longer depend on
/// it at all: they are made on quality, and the lever they pull has the same
/// sign on every family measured, the unmeasured one included (D136).
enum GlassHardware {
  /// Adreno 830 / Impeller-Vulkan, which is where every cycle number in this
  /// project comes from (SM-S938B).
  ///
  /// Declaring this on another Adreno is an extrapolation the host owns: the
  /// laws were fitted on one chip. Declaring it on a Mali or an Xclipse is
  /// wrong in a way that shows up as a proxy recorded at a quarter of the
  /// resolution for a saving nobody has seen.
  adrenoVulkan,

  /// Apple Metal, measured on an M2 iPad Pro on iOS 26 (D56, D71, D119, D128).
  ///
  /// The one family where our whole route has been measured against its own
  /// floor rather than assembled out of other people's grids, and where the
  /// assembled estimate turned out to be wrong (D63 against D127).
  appleMetal,

  /// Anything else, which is most things — every Android device a silent host
  /// runs on. Every price refuses; the choices do not.
  ///
  /// They used to. "The conservative end of every policy" was full resolution
  /// and no merging, and the first unmeasured device anybody ran got 37 fps
  /// from it where a quarter gets 115 and the stock Material 120 (D134). Two
  /// refusals made for one reason multiplied into an atlas larger than the
  /// screen it sampled (D135). The conservative end of a lever whose sign is
  /// measured on every family is the *pulled* end.
  unmeasured;

  /// What can be told without the host saying anything.
  ///
  /// Apple platforms are [appleMetal] — Flutter ships no other backend there —
  /// and everything else is [unmeasured], including every Android device,
  /// because no Dart API names the GPU. This is a floor, not a guess: a host
  /// that knows better declares better.
  static GlassHardware detect() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return GlassHardware.appleMetal;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return GlassHardware.unmeasured;
    }
  }

  /// How this hardware charges for a capture — the input
  /// `ProxyResolutionPolicy.choose` needs.
  ProxyCostModel get captureCostModel {
    switch (this) {
      case GlassHardware.adrenoVulkan:
        return ProxyCostModel.areaCharged;
      case GlassHardware.appleMetal:
        return ProxyCostModel.frameCharged;
      case GlassHardware.unmeasured:
        return ProxyCostModel.unmeasured;
    }
  }

  /// The largest texture this family is *guaranteed* to allocate, in device
  /// pixels a side — the bound [AtlasLayout.fitsTexture] is asked about (D186).
  ///
  /// **Every number here is a specification floor, not a measurement**, and
  /// that is the whole of its authority: Vulkan guarantees
  /// `maxImageDimension2D >= 4096`, Metal's feature-set tables put the oldest
  /// family Flutter still runs on at 8192, and GLES 3.0 guarantees only 2048 —
  /// which no shipping GPU sits at, and which is where this package's own
  /// `shelfWidth` default came from. Real devices are far above all three
  /// (16384 on both Apple GPUs, Xclipse and Adreno, D188/D195), so a host that
  /// knows its device should say so: `GlassProxyPipeline(maxTextureSide: ...)`
  /// overrides this, and raising it buys quality back, because the only
  /// response the pipeline has to the ceiling is a deeper divisor.
  ///
  /// It cannot be detected, which is the same sentence as everything else in
  /// this file, but for once with a way out: the limit *is* observable from
  /// Dart, just not by asking. `GetSize()` reports the size that was requested
  /// rather than the texture's, so the reduction is invisible to arithmetic —
  /// but it is visible in pixels. **Run 2026-09-15 (D188):** ask a snapshot of
  /// `side x 8` whether the texel at `(side - 1, 0)` was drawn — one snapshot
  /// and one readback, through a second ordinary snapshot, never `toByteData`
  /// on the suspect image itself. Both Apple GPUs in reach answered **16384**,
  /// twice the floor below.
  ///
  /// The floor did not move, and that is the finding rather than an omission.
  /// Flutter's own app template deploys to iOS 15, which still runs on the A8
  /// iPad mini 4 and iPad Air 2 — Apple GPU family 2, whose tables say 8192. A
  /// number measured on two machines is not a licence to raise a constant whose
  /// job is the worst device the SDK will install on. The probe's worth is that
  /// a host can now measure instead of guess.
  int get maxTextureSide {
    switch (this) {
      case GlassHardware.appleMetal:
        return 8192;
      case GlassHardware.adrenoVulkan:
      case GlassHardware.unmeasured:
        return 4096;
    }
  }

  /// Which measurements the glass ledger reads itself against.
  GlassSurfaceCostModel get surfaceCostModel {
    switch (this) {
      case GlassHardware.adrenoVulkan:
        return GlassSurfaceCostModel.adrenoCycles;
      case GlassHardware.appleMetal:
        return GlassSurfaceCostModel.metalThroughput;
      case GlassHardware.unmeasured:
        return GlassSurfaceCostModel.unmeasured;
    }
  }
}
