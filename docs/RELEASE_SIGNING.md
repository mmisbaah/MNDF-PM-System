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

For the Windows installer, `installer/build-installer.ps1` creates a disposable staging copy. Production PowerShell signatures are applied only there; the reviewed checkout and provenance-bound build remain unchanged. Because signing changes helper bytes, the builder recreates the staged integrity manifest and signs it with `-ReleaseSigningPrivateKey` using the separately supplied `RELEASE_SIGNING_KEY_PASSPHRASE`. It verifies the staged manifest and package before compilation and always removes staging. Never pass the custody key to rehearsal builds or place it in the repository, output directory, logs, or command history.

Rotate the signing key after suspected compromise or under the organization's approved cryptographic schedule. Promotion must remain paused while the pinned public key is changed through an independently approved deployment action. Preserve old public keys with historical release evidence; never use them to approve new packages.

## Output safety and partial failures

Key and signature outputs use exclusive creation (`wx`), not an existence check
followed by an overwriting write. A concurrent creator causes failure rather than
replacement. Private and public key paths must be different. Existing outputs
are not deleted or replaced automatically; choose new output paths for retries.

Key-pair creation is not a two-file transaction. If public-key creation fails
after the encrypted private key has been written, that private key is preserved
and the command fails. Do not deploy an incomplete pair. Have the key custodian
review it and generate a complete pair at fresh paths. A crash or disk failure
may likewise leave a partial output: verify the completed pair/signature before
use, rather than treating file existence as success.

Run `node --test scripts/release-signing.test.mjs` for disposable-key tests of
existing-file preservation, concurrent signing, mismatched-manifest rejection,
same-path rejection and partial-pair preservation. These tests do not access the
real signing keys. Use a protected local filesystem for custody: exclusive-create
semantics on network shares require separate verification. On Windows, the file
mode bits do not replace Windows ACLs; protect the custody directory beforehand.
