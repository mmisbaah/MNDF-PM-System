# Windows installer

The installer places one immutable, signed release under `C:\PerformanceTracker\releases`. It never embeds or fabricates database passwords, MFA keys, service credentials, TLS private keys, release-signing private keys, or organization records.

The production payload is allowlisted to the prepared standalone application, a pinned portable Node.js 24 runtime (including its license), explicitly named operational scripts, database migrations, and deployment templates. Repository metadata, source-only files, release-gate/build orchestration, build caches, test and lint helpers, local seed tools, browser checks, test output, and development dependencies are excluded. Run the release gate from the controlled release checkout before packaging; do not install the build toolchain on the application host. Unsigned rehearsal packages may retain the wider signed release script inventory for diagnostic parity; they are never production-authorized.

Production compilation uses a disposable staging copy so Authenticode signatures never modify the reviewed checkout or its provenance-bound build output. It signs all staged PowerShell helpers, regenerates the staged full-package manifest, signs that manifest with the offline-custody Ed25519 key, verifies both integrity layers, compiles the installer, signs the EXE, and removes staging even after failure.

Production compilation requires:

- a clean, provenance-recorded standalone release with an Ed25519 release-manifest signature;
- access to the organization-controlled Authenticode certificate private key and the separately guarded Ed25519 release-signing key/passphrase;
- the pinned Inno Setup 6.7.3 compiler whose SHA-256 fingerprint and valid Pyrsys B.V. Authenticode publisher signature are verified before use;
- the separately verified release public key and its recorded fingerprint;
- a Windows SDK signing tool with an independently approved SHA-256 fingerprint and valid Microsoft Authenticode signature, plus an organization-controlled code-signing certificate;
- an Authenticode-signed and RFC 3161 timestamped final installer executable;
- an attended deployment administrator to provision restricted PostgreSQL roles, TLS, protected secrets, ACLs, and the dedicated non-administrator service account.

`build-installer.ps1 -AllowUnsignedRehearsal` exists only for disposable installation testing. Its output is not authorized for production distribution.

The default `TrustedCompilerSha256` pins the reviewed Inno Setup 6.7.3 compiler. A compiler upgrade requires a separately reviewed source change to that fingerprint; do not override it merely to make an unfamiliar binary pass. The installer build record includes the verified compiler hash and publisher subject.

Every successful build creates `<installer>.build.json` using exclusive creation. The builder refuses to replace an existing installer, record, or reserved signature path. The portable version 6 record uses adjacent safe filenames rather than build-machine paths and binds the installer hash to the source commit, release identifier, compiler identity, Windows signing-tool hash/publisher, bundled Node runtime, release trust key, production-helper allowlist, Authenticode signer subject/thumbprint, RFC 3161 timestamp-authority thumbprint, signing status, and UTC creation time. Production builds also create `<installer>.build.json.sig.json` with the offline-custody Ed25519 key and immediately verify it against the pinned public key. Preserve and transfer all three production artifacts together in one directory. Rehearsal records deliberately omit signing-tool and signer identity, remain unsigned, and state `productionAuthorized: false`. Console output is informational and is not a substitute for retained evidence.

Before transferring or running an installer, use `scripts/verify-installer-package.ps1` with explicit installer, build-record, public-key, approved Node-runtime path, and the independently recorded `-ApprovedSigningCertificateThumbprint`, `-ApprovedSignToolSha256`, and `-ApprovedReleasePublicKeySha256`. The reviewed Inno Setup fingerprint is pinned by `-ApprovedCompilerSha256`. Production verification checks the EXE hash and Authenticode signature, matches the actual signer, release tools, and Ed25519 trust key to those independent approvals, validates every recorded fingerprint, checks the exact adjacent sidecar signature path, verifies the Node fingerprint, and only then trusts the record signature. This independent public-key fingerprint breaks the otherwise circular assumption that a record can authorize the key that signed it. `-AllowUnsignedRehearsal` accepts only records explicitly marked non-production and never converts them into deployable artifacts.

Uninstall removes runtime scheduled tasks but deliberately retains configuration, evidence, logs, backups, audit exports, and immutable releases. Those records require a separate authorized retention or destruction decision.
