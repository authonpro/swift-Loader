# Authon Swift SDK

<p align="center">
  <img src="https://authon.pro/logo.png" alt="Authon" width="80" />
  <br/>
  <strong>Official Swift SDK for Authon — Software Licensing & Authentication Platform</strong>
</p>

<p align="center">
  <a href="https://authon.pro">Website</a> •
  <a href="https://authon.pro/docs">Docs</a> •
  <a href="https://discord.gg/MTY79JDFm6">Discord</a> •
  <a href="https://authon.pro/status">Status</a>
</p>

---

## Requirements

- Swift 5.7+, macOS 12+ / iOS 15+
- No external dependencies (uses Foundation URLSession)

## Installation

### Swift Package Manager
```swift
.package(url: "https://github.com/authonpro/sdk-swift", from: "1.0.0")
```

Or copy `Authon.swift` into your Xcode project.

## Quick Start

```swift
import Foundation

let auth = Authon(appId: "your-app-id", apiKey: "your-api-key")

Task {
    await auth.initialize()
    let result = await auth.login(username: "user", password: "pass")
    if result.success {
        print("Level: \(auth.level)")
    }
    await auth.logout()
}
```

## Links

- 🌐 Website: https://authon.pro
- 📖 Docs: https://authon.pro/docs
- 💬 Discord: https://discord.gg/MTY79JDFm6
- 📊 Status: https://authon.pro/status
- 🔗 API Health: https://api.authon.pro/health

## License

MIT
