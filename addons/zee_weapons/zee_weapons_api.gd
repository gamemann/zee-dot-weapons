extends RefCounted

## zee-dot-weapons' API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.
##
## 2: [method ZeeModelCache.set_asset_root] and [method ZeeModelCache.resolve], which a
## delivered game calls to find its own vendored art. A client shell built before them
## would mount such a pack and then fail to compile its client script.

const LEVEL := 2
const OLDEST := 1
