# Maalumi 🌐

Maalumi is an ultra-fast, native macOS web browser engineered in Swift and SwiftUI, powered by WebKit and the automated **MaalumiCore** privacy engine.

## Key Features

- **Native macOS Experience**: Designed to match macOS Human Interface Guidelines with a minimalist, distraction-free interface.
- **LumiShields macOS Engine**: Multi-threaded, heavy-duty ad and tracker blocking supporting up to 149,000 rules per chunk across concurrent CPU cores with persistent disk caching.
- **Deep Core Integration**: Decoupled from [maalumi-core](https://github.com/Heiwanaramu/maalumi-core), automatically receiving upstream Brave engine and filter list updates.
- **Instant Launch & Non-blocking UI**: Persistent disk caching of compiled content rules via `WKContentRuleListStore` for near-instant page load times.

## Building from Source

### Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15.0+ or Swift 5.9+ toolchain

### Build
```bash
swift build -c release
```

### Package DMG
To build the application bundle and generate `dist/Maalumi.dmg`:
```bash
./scripts/package_dmg.sh
```

## Architecture

Maalumi uses a decoupled, two-repository architecture:
1. **[maalumi-core](https://github.com/Heiwanaramu/maalumi-core)**: Standalone Swift library managing Brave Core synchronization, CoreData models, and tracker mitigation.
2. **[maalumi](https://github.com/Heiwanaramu/maalumi)**: The native macOS browser application, user interface, tab manager, and LumiShields content blocking engine.
