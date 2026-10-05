// The thermal vocabulary the host spends staleness against (D205).
//
// Only the vocabulary: the package does not read the device. Flutter carries no
// thermal state, and reading it takes native code on every platform, which this
// package deliberately does not ship — the application passes what it read, from
// whatever source it has, to `GlassHost.thermal`.

/// Thermal pressure, in Apple's four names — the coarser vocabulary of the two,
/// so every Android status maps onto one of them and none of Apple's is
/// invented.
///
/// Android's seven statuses fold as `NONE` → [nominal], `LIGHT` and `MODERATE`
/// → [fair], `SEVERE` → [serious], `CRITICAL`, `EMERGENCY` and `SHUTDOWN` →
/// [critical]. The line between [fair] and [serious] is drawn where both
/// platforms' own documentation first says the user will notice: Apple's
/// `serious` is "system performance is impacted", Android's `SEVERE` is
/// "throttling where UX is largely impacted", and `MODERATE` is "not largely
/// impacted".
enum GlassThermalState { nominal, fair, serious, critical }
