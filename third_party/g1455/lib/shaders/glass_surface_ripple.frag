// The package's glass with the ripple compiled in (D229): `glass_surface.frag`
// behind one define, so the two binaries cannot drift — every line they share
// is one line. The base binary is byte-identical to the file with every
// `GLASS_RIPPLE` block deleted, and `test/shader_targets_test.dart` enforces it.

#define GLASS_RIPPLE
#include "glass_surface.frag"
