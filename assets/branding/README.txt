Branding assets (SVG, PNG, etc.)

App icon + native splash:
  Files:  app_icon.png (launcher icon), app_icon_small.png (splash center image)
  Used by: flutter_launcher_icons (app_icon.png), flutter_native_splash (app_icon_small.png).
  Replace this file with your final artwork, then run:
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

Login / sign-up wordmark:
  File:   login_wordmark.svg
  Used in: lib/auth/pages/login_page.dart (constant kLoginWordmarkAsset)

Replace login_wordmark.svg with your own artwork. If you rename the file,
update kLoginWordmarkAsset in login_page.dart and add the new path under
flutter: assets: in pubspec.yaml if needed.

Tip: use a wide viewBox (e.g. height 32–48) so the logo scales cleanly.
