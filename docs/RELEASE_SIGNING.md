# Release signing and trusted promotion

Release hashes provide integrity only when the manifest itself is trusted. Performance Tracker therefore requires an Ed25519 signature over the exact bytes of every `release-manifest.json` before production promotion.

Create the signing key pair once in an offline release-custody environment:

```powershell
$env:RELEASE_SIGNING_KEY_PASSPHRASE = '<retrieved from separate custody>'
node scripts/release-signing.mjs keygen release-private.pem release-public.pem
```

Keep the encrypted private key and passphrase in separate approved offline custody. Copy only `release-public.pem` to `C:\PerformanceTracker\config\release-signing-public.pem` on the production host and restrict modification to deployment administrators. Record its SHA-256 file fingerprint independently in the signed operational-readiness record. The application service account needs no signing-key access.

After the reviewed build runs `prepare-standalone.ps1`, sign its manifest in the controlled release environment:

```powershell
$env:RELEASE_SIGNING_KEY_PASSPHRASE = '<retrieved from separate custody>'
node scripts/release-signing.mjs sign `
  .next/standalone/release-manifest.json `
  release-private.pem `
  .next/standalone/release-manifest.sig.json
Remove-Item Env:RELEASE_SIGNING_KEY_PASSPHRASE
```

Transfer the immutable release package and detached signature together. `promote-release.ps1` requires `-TrustedPublicKeySha256` from the approved readiness record, checks that the key is outside the releases directory, verifies its fingerprint, and then verifies the signature before it stops or switches anything. A missing signature, changed manifest, substituted public key, invalid signature, mismatched package hash, or unrecognized signature format blocks promotion.

Rotate the signing key after suspected compromise or under the organization's approved cryptographic schedule. Promotion must remain paused while the pinned public key is changed through an independently approved deployment action. Preserve old public keys with historical release evidence; never use them to approve new packages.
