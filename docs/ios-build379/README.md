# iOS build 379 baseline

This branch is reserved for the independently authored iOS build of Folia supplied by the repository owner for authorized modification.

## Artifact identity

- Display name: Folia
- Version: 3.0.6
- Build: 379
- Bundle identifier: `top.izuna.foliaios`
- Minimum iOS: 15.0
- Built with: Xcode 27.0 / iPhoneOS SDK 27.0 (as recorded in Info.plist)
- Original artifact filename: `iPad-Folia-3.0.6-build379-正式版.ipa`
- Original IPA size: 59 MB
- SHA-256: `d2702706ff6dede4533ea895b9fd42c0f718ab1f4d1cfddbcf3e21b1500218de`

## Important status

The uploaded IPA is a compiled application package, not a complete Xcode source project. It contains a compiled iOS app, bundled web assets, and runtime dependencies. This branch is the isolated working baseline; the original IPA binary has **not** been committed here because the connected GitHub file-writing interface does not support uploading a 59 MB binary/release asset.

Do not treat extracted or decompiled files as the original author's complete source project. Before making a rebuildable project, inspect the archive, identify the original build pipeline and distinguish editable web assets from compiled native components.

## Handling requirements

- Keep this branch separate from the repository's existing Folia development line.
- Preserve upstream attribution and applicable license notices.
- Do not commit signing certificates, provisioning secrets, private keys, tokens, or user authentication/session state.
- Keep the untouched original IPA as the immutable reference artifact; record its SHA-256 whenever it is transferred.
- Record each modification and whether it affects web assets, native iOS code, runtime packaging, or signing.

## Next steps

1. Add the original IPA as a GitHub Release asset or Git LFS object using a binary-capable upload path.
2. Inventory the archive and exclude credentials, local state, signatures, and generated caches from any source extraction.
3. Determine which web resources can be edited directly and which native features require reconstructing the iOS project.
4. Establish a reproducible build and signing workflow before changing application behavior.
