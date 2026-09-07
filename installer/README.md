# Windows installer

The installer places one immutable, signed release under `C:\PerformanceTracker\releases`. It never embeds or fabricates database passwords, MFA keys, service credentials, TLS private keys, release-signing private keys, or organization records.

The production payload is allowlisted to the prepared standalone application, a pinned portable Node.js 24 runtime (including its license), explicitly named operational scripts, database migrations, and deployment templates. Repository metadata, source-only files, release-gate/build orchestration, build caches, test and lint helpers, local seed tools, browser checks, test output, and development dependencies are excluded. Run the release gate from the controlled release checkout before packaging; do not install the build toolchain on the application host. Unsigned rehearsal packages may retain the wider signed release script inventory for diagnostic parity; they are never production-authorized.

Production compilation uses a disposable staging copy so Authenticode signatures never modify the reviewed checkout or its provenance-bound build output. It signs all staged PowerShell helpers, regenerates the staged full-package manifest, signs that manifest with the offline-custody Ed25519 key, verifies both integrity layers, compiles the installer, signs the EXE, and removes staging even after failure.

Production compilation requires:

- a clean, provenance-recorded standalone release with an Ed25519 release-manifest signature;
- access to the organization-controlled Authenticode certificate private key and the separately guarded Ed25519 release-signing key/passphrase;
- an approved Inno Setup compiler;
- the separately verified release public key and its recorded fingerprint;
- a Windows SDK signing tool and organization-controlled Authenticode code-signing certificate;
- an Authenticode-signed and RFC 3161 timestamped final installer executable;
- an attended deployment administrator to provision restricted PostgreSQL roles, TLS, protected secrets, ACLs, and the dedicated non-administrator service account.

`build-installer.ps1 -AllowUnsignedRehearsal` exists only for disposable installation testing. Its output is not authorized for production distribution.

Uninstall removes runtime scheduled tasks but deliberately retains configuration, evidence, logs, backups, audit exports, and immutable releases. Those records require a separate authorized retention or destruction decision.
