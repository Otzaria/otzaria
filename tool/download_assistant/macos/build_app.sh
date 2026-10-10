#!/usr/bin/env bash
# בונה את Otzaria-Download-Assistant-macos.zip (Universal: arm64 + x86_64, חתימה ad-hoc).
# התג המוטבע מגיע רק ממשתנה הסביבה OTZARIA_ASSISTANT_RELEASE_TAG, לעולם לא מארגומנט.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
OUT_DIR="${1:-$HERE/build}"
# מוחלט לפני ה-cd שבהמשך, אחרת נתיב יחסי היה מצביע למקום אחר.
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
APP_NAME="Otzaria-Download-Assistant"
EXECUTABLE="DownloadAssistant"
ZIP_NAME="Otzaria-Download-Assistant-macos.zip"
BUNDLE_ID="org.otzaria.download-assistant"

TAG="${OTZARIA_ASSISTANT_RELEASE_TAG:-}"
# בלי מרכאות ובלי לוכסן אין דרך לשבור את קובץ המקור שנוצר; ה-`+` עובר כפי שהוא.
if ! [[ "$TAG" =~ ^[0-9A-Za-z.+_-]*$ ]]; then
  echo "::error::OTZARIA_ASSISTANT_RELEASE_TAG contains characters outside [0-9A-Za-z.+_-]: '$TAG'" >&2
  exit 1
fi

BUILD_INFO="$HERE/Sources/DownloadAssistant/BuildInfo.generated.swift"
# הקובץ במאגר נשאר עם תג ריק; הגרסה המוטבעת קיימת רק בזמן הבנייה.
BUILD_INFO_ORIGINAL="$(cat "$BUILD_INFO")"
trap 'printf "%s\n" "$BUILD_INFO_ORIGINAL" > "$BUILD_INFO"' EXIT
cat > "$BUILD_INFO" <<EOF
// נכתב מחדש ב-build_app.sh מתוך OTZARIA_ASSISTANT_RELEASE_TAG. ריק = בנייה מקומית (latest בלבד).
let embeddedReleaseTag = "$TAG"
EOF

VERSION="${TAG%%+*}"
[ -n "$VERSION" ] || VERSION="0.0.0"
# X.Y.Z.<run> כך שבניות dev של אותה גרסה נבדלות; התג כולו כבר אומת כאן.
BUILD_NUMBER="$VERSION"
RUN="${TAG#*+}"
if [[ "$TAG" == *+* && "$RUN" =~ ^[0-9]+$ ]]; then
  BUILD_NUMBER="$VERSION.$RUN"
fi

# העיצוב הנעוץ (סמלים, תגים, פריימי הספר) — בלעדיו אין בנייה, כמו במסייע ל-Windows.
ART_DIR="$HERE/build/art"
bash "$HERE/fetch_art.sh" "$ART_DIR"

cd "$HERE"
swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BINARY="$BIN_DIR/$EXECUTABLE"
[ -x "$BINARY" ] || { echo "::error::built binary not found at $BINARY" >&2; exit 1; }

ARCHS="$(lipo -archs "$BINARY")"
echo "Architectures: $ARCHS"
for arch in arm64 x86_64; do
  case " $ARCHS " in
    *" $arch "*) ;;
    *) echo "::error::$BINARY is missing the $arch slice ($ARCHS)" >&2; exit 1 ;;
  esac
done

APP="$OUT_DIR/$APP_NAME.app"
# רק מה שהסקריפט עצמו יוצר — לעולם לא תיקיית הפלט שהתקבלה כארגומנט.
rm -rf "$APP" "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
mkdir -p "$APP/Contents/Resources/Art"
cp "$ART_DIR"/*.png "$APP/Contents/Resources/Art/"

# שם האפליקציה ב-Finder וב-Dock בשפת המערכת; הממשק עצמו בוחר שפה לבד (UILanguage.detect).
mkdir -p "$APP/Contents/Resources/he.lproj" "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/he.lproj/InfoPlist.strings" <<'EOF'
"CFBundleDisplayName" = "מסייע הורדה לאוצריא";
"CFBundleName" = "מסייע אוצריא";
EOF
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOF'
"CFBundleDisplayName" = "Otzaria Download Assistant";
"CFBundleName" = "Otzaria Assistant";
EOF

# אייקון המסייע, מאותו מקור כמו ה-.ico של Windows. כישלון כאן קוסמטי — המסייע נבנה גם בלעדיו.
make_icon() {
  local source="$REPO_ROOT/installer/download_assistant_icon.png" size double
  mkdir -p "$ICONSET" || return 1
  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$source" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null || return 1
    sips -z "$double" "$double" "$source" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null || return 1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
}
ICON_PLIST=""
ICONSET="$OUT_DIR/AppIcon.iconset"
if make_icon; then
  ICON_PLIST="  <key>CFBundleIconFile</key>
  <string>AppIcon</string>"
else
  echo "::warning::could not build the assistant icon; continuing without it"
fi
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>he</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>he</string>
    <string>en</string>
  </array>
  <key>CFBundleDisplayName</key>
  <string>מסייע הורדה לאוצריא</string>
  <key>CFBundleName</key>
  <string>מסייע אוצריא</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
$ICON_PLIST
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

(cd "$OUT_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME")
echo "Built $OUT_DIR/$ZIP_NAME (tag: ${TAG:-<none>})"
