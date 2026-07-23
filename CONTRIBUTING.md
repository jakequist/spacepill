# Contributing to SpacePill 🚀

We'd love your help! Whether it's a bug fix, new feature, or documentation improvement, every contribution counts.

## 🛠 Getting Started

1.  **Fork** the repository.
2.  **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/spacepill.git`
3.  **Create a branch**: `git checkout -b feature/your-feature-name`
4.  **Install dependencies**: No external dependencies! Just need Xcode 15.0+ or Swift 5.9+.
5.  **Set up signing (once)**: `./bin/dev-cert.sh`. SpacePill needs Accessibility and Input Monitoring permission, and macOS ties those grants to the app's code signature — without a stable signing identity every rebuild looks like a new app and silently loses them.
6.  **Run the app**: `./bin/start.sh` (add `--debug` for much faster compiles).
7.  **Watch the logs**: `./bin/logs.sh`. SpacePill logs via `os.Logger`, not `print` — a menu bar app has no terminal attached, so `print` output goes nowhere.

Don't run `.build/release/SpacePill` directly. Without an `.app` bundle it has no bundle identifier, which disables Launch at Login and gives it a different permissions identity than the real app. `bin/start.sh` builds a proper bundle for you.

## 🧪 Testing

SpacePill relies on private SkyLight APIs and global hotkeys, so verification is manual and visual. Please test your changes across different space configurations (multiple monitors, full-screen apps, more than 10 Spaces).

Worth re-checking by hand after almost any change:

- All three hotkeys — **and** again after opening Preferences.
- The pill on both labelled and unlabelled Spaces.
- Space detection via `⌃←→`, via Mission Control, and with >10 Spaces.
- A clean first run (`mv ~/.spacepill ~/.spacepill.bak` and relaunch).

## 📝 Guidelines

- Follow existing code style (Swift standard, 4-space indent).
- Keep it lightweight! SpacePill aims for a minimal memory and CPU footprint.
- Use `Log.<category>` from `Utils/Log.swift` rather than `print`.
- Space labels/colours are keyed by Space **UUID**, not index — indices shift whenever a Space is added or removed.
- Never force-unwrap the result of a SkyLight call; those private APIs can change in any macOS release.
- Bump `./VERSION` only; `Info.plist` is stamped at package time.
- Update the README if you add new features or change hotkeys.

## 🚀 Submitting a Pull Request

1.  **Commit** your changes with a clear message.
2.  **Push** to your fork: `git push origin feature/your-feature-name`
3.  **Open a Pull Request** against the `main` branch.

## 🔒 Security

If you find a security vulnerability, please do not open an issue. Instead, contact the maintainer directly.

---
Built with ❤️ by [Jake Quist](https://github.com/jakequist)
