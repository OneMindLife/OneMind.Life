#!/usr/bin/env bash
#
# prepare_open_source.sh
#
# Creates a clean open source release of OneMind by copying only essential files
# and excluding secrets, credentials, and personal files.
#
# Usage: ./scripts/prepare_open_source.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source and destination directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"
DEST_DIR="${SOURCE_DIR}/../onemind-oss"

echo -e "${GREEN}=== OneMind Open Source Release Preparation ===${NC}"
echo "Source: $SOURCE_DIR"
echo "Destination: $DEST_DIR"
echo ""

# Clean destination if it exists
if [ -d "$DEST_DIR" ]; then
    echo -e "${YELLOW}Removing existing destination directory...${NC}"
    rm -rf "$DEST_DIR"
fi

# Create destination directory
mkdir -p "$DEST_DIR"

# Function to copy directory with exclusions
copy_dir() {
    local src="$1"
    local dest="$2"
    shift 2
    local excludes=("$@")

    if [ -d "$SOURCE_DIR/$src" ]; then
        mkdir -p "$DEST_DIR/$dest"
        rsync -a --quiet \
            "${excludes[@]/#/--exclude=}" \
            "$SOURCE_DIR/$src/" "$DEST_DIR/$dest/"
        echo -e "  ${GREEN}✓${NC} $src"
    else
        echo -e "  ${YELLOW}⚠${NC} $src (not found, skipping)"
    fi
}

# Function to copy single file
copy_file() {
    local src="$1"
    local dest="${2:-$1}"

    if [ -f "$SOURCE_DIR/$src" ]; then
        mkdir -p "$(dirname "$DEST_DIR/$dest")"
        cp "$SOURCE_DIR/$src" "$DEST_DIR/$dest"
        echo -e "  ${GREEN}✓${NC} $src"
    else
        echo -e "  ${YELLOW}⚠${NC} $src (not found, skipping)"
    fi
}

echo -e "${GREEN}Copying Flutter app files...${NC}"
copy_dir "lib" "lib" "firebase_options.dart"
copy_dir "test" "test"
copy_dir "web" "web"
copy_dir "assets" "assets"

echo ""
echo -e "${GREEN}Copying Android files (excluding google-services.json)...${NC}"
copy_dir "android" "android" "google-services.json" "app/google-services.json" "*.keystore" "key.properties"

echo ""
echo -e "${GREEN}Copying iOS files (excluding GoogleService-Info.plist)...${NC}"
copy_dir "ios" "ios" "GoogleService-Info.plist" "Runner/GoogleService-Info.plist"

echo ""
echo -e "${GREEN}Copying Supabase files...${NC}"
copy_dir "supabase/migrations" "supabase/migrations"
copy_dir "supabase/functions" "supabase/functions" ".env"
copy_dir "supabase/tests" "supabase/tests"
copy_file "supabase/config.toml"

echo ""
echo -e "${GREEN}Copying scripts...${NC}"
copy_file "scripts/setup_local_cron.sql"

echo ""
echo -e "${GREEN}Copying documentation...${NC}"
copy_dir "docs" "docs"
copy_file "README.md"
copy_file "CLAUDE.md"

echo ""
echo -e "${GREEN}Copying configuration files...${NC}"
copy_file "pubspec.yaml"
copy_file "pubspec.lock"
copy_file "analysis_options.yaml"
copy_file "l10n.yaml"
copy_file ".gitignore"
copy_file "firebase.json"

echo ""
echo -e "${GREEN}Copying template files...${NC}"
copy_file ".env.example"
if [ -f "$SOURCE_DIR/supabase/functions/.env.example" ]; then
    copy_file "supabase/functions/.env.example"
fi

echo ""
echo -e "${GREEN}Copying license...${NC}"
copy_file "LICENSE"

# Create placeholder files for Firebase configs
echo ""
echo -e "${GREEN}Creating placeholder files for Firebase configs...${NC}"

# Android google-services.json placeholder
mkdir -p "$DEST_DIR/android/app"
cat > "$DEST_DIR/android/app/google-services.json.example" << 'EOF'
{
  "_comment": "Copy this file to google-services.json and fill in your Firebase project details",
  "project_info": {
    "project_number": "YOUR_PROJECT_NUMBER",
    "project_id": "YOUR_PROJECT_ID",
    "storage_bucket": "YOUR_PROJECT_ID.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "YOUR_APP_ID",
        "android_client_info": {
          "package_name": "com.onemindlife.onemind"
        }
      },
      "oauth_client": [],
      "api_key": [
        {
          "current_key": "YOUR_API_KEY"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": []
        }
      }
    }
  ],
  "configuration_version": "1"
}
EOF
echo -e "  ${GREEN}✓${NC} android/app/google-services.json.example"

# iOS GoogleService-Info.plist placeholder
mkdir -p "$DEST_DIR/ios/Runner"
cat > "$DEST_DIR/ios/Runner/GoogleService-Info.plist.example" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Copy this file to GoogleService-Info.plist and fill in your Firebase project details -->
    <key>API_KEY</key>
    <string>YOUR_API_KEY</string>
    <key>GCM_SENDER_ID</key>
    <string>YOUR_GCM_SENDER_ID</string>
    <key>PLIST_VERSION</key>
    <string>1</string>
    <key>BUNDLE_ID</key>
    <string>com.onemindlife.onemind</string>
    <key>PROJECT_ID</key>
    <string>YOUR_PROJECT_ID</string>
    <key>STORAGE_BUCKET</key>
    <string>YOUR_PROJECT_ID.appspot.com</string>
    <key>IS_ADS_ENABLED</key>
    <false/>
    <key>IS_ANALYTICS_ENABLED</key>
    <false/>
    <key>IS_APPINVITE_ENABLED</key>
    <true/>
    <key>IS_GCM_ENABLED</key>
    <true/>
    <key>IS_SIGNIN_ENABLED</key>
    <true/>
    <key>GOOGLE_APP_ID</key>
    <string>YOUR_GOOGLE_APP_ID</string>
</dict>
</plist>
EOF
echo -e "  ${GREEN}✓${NC} ios/Runner/GoogleService-Info.plist.example"

# Create firebase_options.dart placeholder
mkdir -p "$DEST_DIR/lib"
cat > "$DEST_DIR/lib/firebase_options.dart.example" << 'EOF'
// Copy this file to firebase_options.dart and fill in your Firebase project details
// You can generate this file using: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    measurementId: 'YOUR_MEASUREMENT_ID',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.onemindlife.onemind',
  );
}
EOF
echo -e "  ${GREEN}✓${NC} lib/firebase_options.dart.example"

# Sanitize production references
echo ""
echo -e "${GREEN}Sanitizing production references...${NC}"

# Supabase config
if [ -f "$DEST_DIR/lib/config/supabase_config.dart" ]; then
    sed -i "s|https://[a-z0-9]*\.supabase\.co|https://YOUR_PROJECT_REF.supabase.co|g" "$DEST_DIR/lib/config/supabase_config.dart"
    sed -i "s|'eyJ[^']*'|'YOUR_SUPABASE_ANON_KEY'|g" "$DEST_DIR/lib/config/supabase_config.dart"
    echo -e "  ${GREEN}✓${NC} lib/config/supabase_config.dart"
fi

# Replace Supabase project ref in all SQL and TypeScript files
find "$DEST_DIR" -type f \( -name "*.sql" -o -name "*.ts" \) -exec sed -i 's/ccyuxrtrklgpkzcryzpj/YOUR_PROJECT_REF/g' {} \;
echo -e "  ${GREEN}✓${NC} Supabase project refs in migrations/functions"

# Replace domain references
find "$DEST_DIR" -type f \( -name "*.dart" -o -name "*.ts" \) -exec sed -i 's/onemind\.life/YOUR_DOMAIN/g' {} \;
echo -e "  ${GREEN}✓${NC} Domain references (onemind.life -> YOUR_DOMAIN)"

# Replace personal email
find "$DEST_DIR" -type f \( -name "*.dart" -o -name "*.ts" \) -exec sed -i 's/joel@YOUR_DOMAIN/your-email@YOUR_DOMAIN/g' {} \;
echo -e "  ${GREEN}✓${NC} Personal email references"

# Create firebase_options_stub.dart for OSS
cat > "$DEST_DIR/lib/firebase_options_stub.dart" << 'STUBEOF'
// Stub file for when Firebase is not configured.
// Generate the real firebase_options.dart by running: flutterfire configure
//
// See: https://firebase.flutter.dev/docs/cli/

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Stub Firebase options when not configured.
/// Throws an error explaining how to set up Firebase.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured. Run `flutterfire configure` to generate firebase_options.dart',
    );
  }
}
STUBEOF
echo -e "  ${GREEN}✓${NC} lib/firebase_options_stub.dart created"

# Update main.dart to use the stub
if [ -f "$DEST_DIR/lib/main.dart" ]; then
    sed -i "s|import 'firebase_options.dart';|// Firebase options - generate with: flutterfire configure\n// To enable Firebase: run \`flutterfire configure\` which creates firebase_options.dart\n// Then change this import from firebase_options_stub.dart to firebase_options.dart\nimport 'firebase_options_stub.dart';|g" "$DEST_DIR/lib/main.dart"
    # Fix the depend_on_referenced_packages lint
    sed -i "s|import 'package:flutter_web_plugins/url_strategy.dart';|// ignore: depend_on_referenced_packages\nimport 'package:flutter_web_plugins/url_strategy.dart';|g" "$DEST_DIR/lib/main.dart"
    echo -e "  ${GREEN}✓${NC} lib/main.dart updated for Firebase stub"
fi

# Scan for leaked secrets
echo ""
echo -e "${GREEN}Scanning for potential leaked secrets...${NC}"

SECRET_PATTERNS=(
    "sk_test_"
    "pk_test_"
    "sk_live_"
    "pk_live_"
    "re_[a-zA-Z0-9]{20,}"
    "SUPABASE_ANON_KEY"
    "SUPABASE_SERVICE_ROLE_KEY"
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    "STRIPE_"
    "whsec_"
    "price_"
    "prod_"
)

LEAKED=0
for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -rq "$pattern" "$DEST_DIR" --include="*.dart" --include="*.json" --include="*.yaml" --include="*.toml" --include="*.sql" --include="*.ts" --include="*.js" 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Found potential secret matching: $pattern"
        grep -rn "$pattern" "$DEST_DIR" --include="*.dart" --include="*.json" --include="*.yaml" --include="*.toml" --include="*.sql" --include="*.ts" --include="*.js" 2>/dev/null | head -5
        LEAKED=1
    fi
done

if [ $LEAKED -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} No obvious secrets found"
else
    echo ""
    echo -e "${RED}WARNING: Potential secrets detected! Review the files above before publishing.${NC}"
fi

# Verify critical files
echo ""
echo -e "${GREEN}Verifying critical files...${NC}"

CRITICAL_FILES=(
    "LICENSE"
    "README.md"
    "pubspec.yaml"
    "lib/main.dart"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$DEST_DIR/$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file exists"
    else
        echo -e "  ${RED}✗${NC} $file missing!"
    fi
done

# Verify excluded files
echo ""
echo -e "${GREEN}Verifying excluded files are NOT present...${NC}"

EXCLUDED_FILES=(
    ".env"
    "supabase/functions/.env"
    "supabase/.env.local"
    "android/app/google-services.json"
    "ios/Runner/GoogleService-Info.plist"
    "lib/firebase_options.dart"
    ".firebaserc"
    "outreach_emails.md"
    "OPEN_SOURCE_PLAN.md"
)

for file in "${EXCLUDED_FILES[@]}"; do
    if [ -f "$DEST_DIR/$file" ]; then
        echo -e "  ${RED}✗${NC} $file should NOT be present!"
    else
        echo -e "  ${GREEN}✓${NC} $file correctly excluded"
    fi
done

# Summary
echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "Open source release prepared at: $DEST_DIR"
echo ""
echo "Next steps:"
echo "  1. Review the output directory for completeness"
echo "  2. Verify no secrets leaked (check warnings above)"
echo "  3. Initialize git repository:"
echo "     cd $DEST_DIR"
echo "     git init"
echo "     git add ."
echo "     git commit -m 'Initial open source release'"
echo ""
echo "  4. Test the build:"
echo "     flutter pub get"
echo "     flutter analyze"
echo ""
