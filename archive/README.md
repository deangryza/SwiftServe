# Archived Flutter Sources

These directories preserve superseded code and generated platform files. They are intentionally excluded from active build and analysis commands.

- `flutter_root_legacy/` contains the original root Flutter application and its old `swiftserve-f9fe6` Firebase configuration.
- `flutter_mobile_shell/` contains the unused generated Flutter shell formerly located directly under `mobile/`.
- `canonical_non_mobile_platforms/` preserves the web and desktop runners removed from the Android/iOS-only canonical application, including pre-existing local generated-plugin changes.

Do not copy archived Firebase configuration into `mobile/my_app`.
