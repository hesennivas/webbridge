# webbridge

a native macos cockpit for debugging android & ios webviews.

## install

both methods build from source, so they need the xcode 26 toolchain (swift 6).

```bash
brew install hesennivas/tap/webbridge
# or
curl -fsSL https://webbridge.up.railway.app/install.sh | bash
```

## the app

```bash
swift run          # dev
scripts/make-app.sh # builds build/WebBridge.app
open build/WebBridge.app
```

## landing site

the site lives in `web/`. to run it locally:

```bash
cd web
npm install
npm run dev
```
