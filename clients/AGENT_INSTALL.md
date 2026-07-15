# Tailscale Agent — Installation & Enrollment Guide

> Headscale is API-compatible with the official Tailscale client. You do **not** install a special client — you install *Tailscale* and point it at your Headscale server via `--login-server`.

**Server URL:** `https://hs.example.com` (replace with your deployed FQDN)
**Web UI:** `https://hs.example.com/web` — see [`docs/WEB_UI.md`](../docs/WEB_UI.md) and [`docs/UI_BASIC_AUTH.md`](../docs/UI_BASIC_AUTH.md)

To onboard any device, an admin first runs:

```bash
./scripts/hs-add-device <your-username> [--tags tag:laptop] [--ephemeral]
```

That prints:
- a one-line `tailscale up …` command
- a QR code for mobile
- a `tailscale://` deep-link
- the Web UI URL

Then follow the OS-specific section below.

---

## 🐧 Linux — Fedora

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
sudo dnf install -y tailscale
sudo systemctl enable --now tailscaled

# Onboard (paste the command from hs-add-device):
sudo tailscale up --login-server https://hs.example.com --authkey tskey-XXXX

# Verify
tailscale status
tailscale ip -4
```

## 🐧 Linux — Ubuntu / Debian

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --login-server https://hs.example.com --authkey tskey-XXXX
```

## 🐧 Linux — Arch / Manjaro

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up --login-server https://hs.example.com --authkey tskey-XXXX
```

## 🐳 Kubernetes sidecar

Use the official `tailscale/tailscale` image with `TS_EXTRA_ARGS`:

```yaml
env:
  - { name: TS_HOSTNAME,   value: my-service }
  - { name: TS_AUTHKEY,    valueFrom: { secretKeyRef: { name: ts, key: authkey } } }
  - { name: TS_EXTRA_ARGS, value: "--login-server=https://hs.example.com --advertise-tags=tag:server" }
  - { name: TS_STATE_DIR,  value: /var/lib/tailscale }
  - { name: TS_USERSPACE,  value: "true" }
```

---

## 🍎 macOS

The App Store build of Tailscale does **not** support custom login servers. Use the standalone build:

```bash
# 1. Download the standalone .pkg
open https://pkgs.tailscale.com/stable/#macos

# 2. After install, from the menu-bar icon:
#      Debug → Custom login server → https://hs.example.com

# Or fully CLI:
/Applications/Tailscale.app/Contents/MacOS/Tailscale up \
  --login-server=https://hs.example.com --authkey=tskey-XXXX
```

## 🪟 Windows

Custom login servers need a registry tweak *before* first sign-in:

```powershell
# Run as Administrator:
reg add HKLM\Software\Tailscale /v LoginURL /t REG_SZ /d https://hs.example.com /f

# Install
winget install tailscale.tailscale
# or download from https://pkgs.tailscale.com/stable/#windows

# Sign in
tailscale up --login-server=https://hs.example.com --authkey=tskey-XXXX
```

---

## 📱 iOS / iPadOS

The App Store build requires unlocking a hidden debug menu:

1. Install **Tailscale** from the App Store.
2. Open the app → tap the account menu (top-right) → tap the **version number five times** to reveal the debug menu.
3. Tap **Alternate coordination server URL** → enter `https://hs.example.com` → save.
4. Sign out and back in.
5. Scan the QR code from `hs-add-device` — or tap the deep-link `tailscale://…`.

## 🤖 Android

1. Install **Tailscale** from Play Store or F-Droid.
2. Open the app → three-dot menu → **Change server** → `https://hs.example.com`.
3. Scan the QR code from `hs-add-device`.

*(Some Android builds require enabling the debug menu the same way as iOS: tap the version string five times.)*

---

## 🔒 What each user should know

- Your device gets a `100.64.x.y` IP in the tailnet — never a public IP.
- MagicDNS names look like `laptop-alice.hs.internal` (base domain per `server.baseDomain`).
- Temporarily disconnect: `tailscale down` (or toggle in the app).
- Leave permanently: `tailscale logout` and ask an admin to delete the node with `headscale nodes delete -i <id>`.
- Manage your own tailnet in the browser: `https://hs.example.com/web` (may require Basic Auth first).

## 🆘 Troubleshooting

| Symptom | Fix |
|---|---|
| `tailscale up` hangs on "Waiting for auth" | Confirm `server_url` in headscale config matches EXACTLY what clients pass to `--login-server` (including https and no trailing slash). |
| Can ping tailnet IPs but MagicDNS names fail | Ensure `dns.magic_dns: true` on the server; run `tailscale up --accept-dns`. |
| Only some peers reachable | Check ACL policy (`policy.hujson`) — deny-all default may block traffic you expected. |
| High latency between two nodes | They're falling back to DERP relay instead of direct. Check STUN (UDP 3478) is exposed publicly. |
| UI page returns 401 | Basic Auth is on — see [`docs/UI_BASIC_AUTH.md`](../docs/UI_BASIC_AUTH.md). |
| UI says "Missing Bearer Prefix" | No API key configured. Create one via `headscale apikeys create` and paste into Settings. |
