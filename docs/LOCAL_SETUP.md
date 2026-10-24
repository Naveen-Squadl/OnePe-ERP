# Running OnePe POS locally

Step-by-step guide to run the full stack (Postgres → API → Flutter app) on your Mac, and to build
the app so that **other devices on the same Wi-Fi** (phones, tablets, another laptop) can use it via
your Mac's local IP address.

```
 Flutter app (web / Android / iOS)  ──HTTP──▶  Node API :4000  ──▶  Postgres :5432 (Docker)
```

Devices only ever talk to the **API**. Postgres stays private to your Mac.

---

## 1. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Docker Desktop | any recent | `docker --version` |
| Node.js | 22 or newer | `node -v` |
| Flutter | 3.41 (Dart 3.11) | `flutter --version` |
| Python 3 | for serving the web build | `python3 --version` |
| Android Studio / SDK | only for Android builds | `flutter doctor` |
| Xcode | only for iOS builds | `flutter doctor` |

Run `flutter doctor` once and fix anything it flags for the platforms you need.

---

## 2. Start the database

```bash
open -a Docker                 # make sure Docker Desktop is running
cd ~/Desktop/OnePe_POS_ERP
docker compose up -d           # Postgres 16 on localhost:5432 (onepe / onepe / onepe_pos)
docker compose ps              # should show the db container as "running"
```

---

## 3. Start the API

```bash
cd backend
cp .env.example .env           # first time only; change JWT_SECRET for anything beyond local dev
npm install                    # first time / after package changes
npx prisma migrate deploy      # apply DB migrations
npm run db:seed                # idempotent: super admin + demo bakery
npm run dev                    # API on http://localhost:4000 (auto-reloads)
```

The server listens on **all network interfaces**, so it is also reachable at
`http://<your-mac-ip>:4000` from other devices — no extra config needed.

Quick check: open <http://localhost:4000/health> in a browser; you should get a JSON
response rather than "connection refused".

Seeded logins:

| Role        | Email                 | Password      |
|-------------|-----------------------|---------------|
| Super Admin | admin@onepe.local     | ChangeMe@123  |
| Shop Admin  | demo@onepe.local      | Demo@1234     |
| Cashier     | cashier@onepe.local   | Cashier@123   |

---

## 4. Run the Flutter app on this Mac (development)

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:4000
```

`API_URL` is baked in at build time (see `app/lib/core/config.dart`); the default is
`http://localhost:4000`.

---

## 5. Build for access over your local IP (LAN / Wi-Fi)

`localhost` on a phone means *the phone itself*, so for any other device you must build the app with
your **Mac's LAN IP** as `API_URL`.

### 5.1 Find your Mac's local IP

```bash
ipconfig getifaddr en0         # Wi-Fi  (e.g. 192.168.0.31)
ipconfig getifaddr en1         # try this if en0 prints nothing (Ethernet / other adapter)
```

Put it in a shell variable so the commands below can be copy-pasted:

```bash
export LAN_IP=$(ipconfig getifaddr en0)
echo $LAN_IP
```

Then confirm the API is reachable over that IP — first from the Mac, then from the phone's browser:

```bash
curl http://$LAN_IP:4000/health
```

> The IP is assigned by your router and can change (it was `192.168.0.31` on 2026-10-15). If the app
> suddenly can't connect, re-check the IP and rebuild. Reserving a fixed IP for your Mac in the
> router's DHCP settings avoids this.

### 5.2 Web build served on the LAN

```bash
cd app
flutter build web --release --dart-define=API_URL=http://$LAN_IP:4000
cd build/web
python3 -m http.server 8080 --bind 0.0.0.0
```

Open on any device on the same Wi-Fi: `http://<LAN_IP>:8080`

- `--bind 0.0.0.0` exposes the site on the LAN. Use `--bind 127.0.0.1` if you only want it on this Mac.
- Flutter web caches aggressively — after a rebuild, load `http://<LAN_IP>:8080/?v=2#/pos`
  (bump the number) or hard-refresh.
- Camera features (barcode scanning) need HTTPS or `localhost` in most mobile browsers, so they may
  not work over plain `http://<LAN_IP>`. Use the Android/iOS app for scanning.

### 5.3 Android APK (install over Wi-Fi)

```bash
cd app
flutter build apk --release --dart-define=API_URL=http://$LAN_IP:4000
# output: build/app/outputs/flutter-apk/app-release.apk
```

Install it:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk   # phone connected via USB
```

…or copy the `.apk` to the phone (AirDrop/Drive/WhatsApp) and open it (allow "Install unknown apps").

`android:usesCleartextTraffic="true"` is already set in `AndroidManifest.xml`, which is what allows
plain `http://` to your Mac. Remove it for production (HTTPS).

**Alternatives that don't depend on the IP:**

```bash
# USB cable – phone reaches the Mac's localhost through adb
adb reverse tcp:4000 tcp:4000
flutter run --release --dart-define=API_URL=http://localhost:4000

# Android emulator – 10.0.2.2 is the host Mac
flutter run --dart-define=API_URL=http://10.0.2.2:4000
```

(`adb reverse` must be re-run each time the phone is reconnected.)

### 5.4 iOS (device on the same Wi-Fi)

```bash
cd app
flutter run --release --dart-define=API_URL=http://$LAN_IP:4000      # device plugged in, trusted
# or an archive for distribution:
flutter build ipa --release --dart-define=API_URL=http://$LAN_IP:4000
```

iOS blocks plain `http://` by default (App Transport Security). For local testing add this to
`app/ios/Runner/Info.plist` inside the top-level `<dict>` — **do not ship it to production**:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

You also need a signing team set in Xcode (`open ios/Runner.xcworkspace` → Runner → Signing &
Capabilities). iOS 14+ will ask the user to allow **Local Network** access the first time — tap Allow.

> Android and iOS builds have not yet been verified on a physical device.

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows a network/connection error on a phone | Phone and Mac must be on the **same Wi-Fi** (not guest network, no VPN). Open `http://<LAN_IP>:4000/health` in the phone's browser to test. |
| Works on Mac, not on phone | macOS firewall: System Settings → Network → Firewall → allow incoming connections for `node` (and `python3` for the web build), or temporarily turn it off. |
| Worked yesterday, not today | The Mac's IP changed — run `ipconfig getifaddr en0` and rebuild with the new IP. |
| `ECONNREFUSED ...:5432` from the API | Docker / Postgres not running: `open -a Docker && docker compose up -d`. |
| `Missing env var JWT_SECRET` | `backend/.env` is missing — `cp .env.example .env`. |
| Product photos don't load | They're served by the API at `/uploads`; check `API_URL` points at the same API the photos were uploaded to. |
| Old UI after rebuilding web | Browser cache — use `?v=N` in the URL or a hard refresh / private window. |
| `adb: no devices` | Enable Developer options → USB debugging on the phone, accept the RSA prompt, re-plug. |

---

## 7. Stopping everything

```bash
# Ctrl+C in the terminals running `npm run dev` and `python3 -m http.server`
docker compose down            # stop Postgres (data is kept in the Docker volume)
```
