# Publishing

Recommended GitHub setup:

1. Commit only source files.
2. Do not commit `dist/`.
3. Build release files locally with:

   ```bash
   script/package_release.sh
   ```

4. Upload the generated zip files from `dist/` to GitHub Releases.

The source repository should not include:

- generated app bundles
- local code signing products
- debug screenshots
- screen recordings
- user-specific configs

For public distribution, notarization is recommended. The local build scripts do
not notarize the app.

