#!/usr/bin/env bash
# Builds the web app with the reCAPTCHA Enterprise site key (public, tied to
# cipher-eye.web.app / cipher-eye.firebaseapp.com / localhost) and deploys it
# to Firebase Hosting.
set -euo pipefail
cd "$(dirname "$0")/.."
RECAPTCHA_SITE_KEY="${RECAPTCHA_SITE_KEY:-6LcD1ootAAAAAKyRw0nWI-6QoDMpYNkA6iffuVhK}"
flutter build web --release --dart-define=RECAPTCHA_SITE_KEY="$RECAPTCHA_SITE_KEY"
firebase deploy --only hosting --project cipher-eye
