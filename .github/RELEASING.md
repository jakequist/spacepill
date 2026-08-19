# Releasing SpacePill

Releases and the docs site are automated with GitHub Actions. This is the
operator's guide: how to cut a release, how the pipeline works, and the one-time
setup that turns unsigned previews into signed, notarized builds.

## TL;DR — cut a release

**Actions tab → Release → Run workflow → pick `minor` → Run.**

That bumps `VERSION`, tags it, builds, and publishes a GitHub Release with the
DMG. Done.

Prefer the command line? Just push a tag:

```bash
echo 1.3.0 > VERSION && git commit -am "Release v1.3.0"
git tag v1.3.0 && git push origin main v1.3.0
```

The tag push triggers the same build-and-publish path.

## The three workflows

| File | Trigger | What it does |
| :-- | :-- | :-- |
| `ci.yml` | every push to `main` / PR | `swift build` + `./bin/test.sh`. Skips doc-only changes. |
| `release.yml` | manual dispatch, or a `v*` tag | version → tag → build → sign (if configured) → DMG → Release |
| `pages.yml` | push to `main` under `docs/**` or `.assets/**` | deploys the site to GitHub Pages |

Releases and site deploys are **decoupled** on purpose — a typo fix on the site
ships immediately without cutting a version, and a release doesn't wait on docs.

`release.yml` reuses `bin/package.sh`, the same script that packages locally, so
CI and a hand-run `./bin/release.sh` build the artifact the same way. There is
one build engine, not two.

## Signing: unsigned today, signed when you're ready

**Out of the box the release is ad-hoc signed and published as a developer
preview.** That is intentional and safe while there are no users:

- Gatekeeper warns on first launch (right-click → Open to bypass).
- `spacepill update` refuses to auto-install it, because its signature check
  demands a Developer ID — exactly the guard you want.

The moment you add the signing secrets below, the *same* workflow produces
signed, notarized DMGs. No YAML changes.

### Secrets to add (repo → Settings → Secrets and variables → Actions)

| Secret | What it is |
| :-- | :-- |
| `DEVELOPER_ID_CERT_P12_BASE64` | Your "Developer ID Application" cert **and private key**, exported from Keychain Access as a `.p12`, then `base64`-encoded. |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you set on that `.p12` export. |
| `NOTARY_APPLE_ID` | The Apple ID used for notarization. |
| `NOTARY_APP_PASSWORD` | An **app-specific password** for that Apple ID (appleid.apple.com → Sign-In and Security → App-Specific Passwords). Not your real password. |
| `APPLE_TEAM_ID` | Your team ID — `A8AEV8Y5TT` for Quist Software. |

Export the cert like this:

```bash
# In Keychain Access: find "Developer ID Application: … (A8AEV8Y5TT)",
# expand it, select BOTH the cert and its private key, right-click → Export
# as certs.p12 with a password, then:
base64 -i certs.p12 | pbcopy    # paste into DEVELOPER_ID_CERT_P12_BASE64
```

`release.yml` imports the cert into an ephemeral keychain that is discarded when
the runner is torn down; the private key never persists.

> **Upgrade path:** app-specific-password notarization works and is the least
> setup. When you want something more robust, switch `notarytool` to an App
> Store Connect **API key** (`.p8`) — it doesn't expire, is scoped, and is
> revocable independently. That's a small change to `bin/package.sh`'s notarize
> call plus three different secrets; worth doing before you have real users.

## One-time repo settings

1. **Pages (required once):** Settings → Pages → Source → **GitHub Actions**.
   The workflow can't create the Pages site itself on this repo (the token isn't
   allowed to), so until you flip this, `pages.yml` fails with *"verify that the
   repository has Pages enabled"*. After enabling, re-run the workflow or push
   any `docs/` change.
2. **URL:** the site publishes at the default
   **`https://jakequist.github.io/spacepill/`** — no custom domain and no `CNAME`
   file. (`jakequist.com` is a separate Vercel site, unrelated to GitHub Pages.)
   If you ever want SpacePill under a custom domain, that's a Pages custom-domain
   setup, distinct from Vercel.
3. **Branch protection:** the release job pushes the version bump commit
   straight to `main`. If you protect `main`, allow `github-actions[bot]` to
   bypass, or the release will fail at the push step.

## Version numbering

`VERSION` (repo root) is the single source of truth. `Info.plist` carries a
placeholder that `bin/package.sh` stamps at build time — never hand-edit the
plist version. The dispatch workflow bumps `VERSION` for you; only edit it by
hand if you're cutting a release via a manual tag push.

## If a release fails partway

The steps are ordered so the irreversible one — publishing the Release — comes
after the build and notarization succeed. If it fails before that, nothing is
published; fix and re-run. If the tag was already created but the release
wasn't, delete the tag (`git push --delete origin vX.Y.Z`) and re-run, or push
it again. The workflow refuses to clobber a release that already exists.
