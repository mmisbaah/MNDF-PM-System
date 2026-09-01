# Windows installer

The installer places one immutable, signed release under `C:\PerformanceTracker\releases`. It never embeds or fabricates database passwords, MFA keys, service credentials, TLS private keys, release-signing private keys, or organization records.

Production compilation requires:

- a clean, provenance-recorded standalone release with an Ed25519 release-manifest signature;
- valid Authenticode signatures on every packaged PowerShell helper;
- an approved Inno Setup compiler;
- the separately verified release public key and its recorded fingerprint;
- a Windows SDK signing tool and organization-controlled Authenticode code-signing certificate;
- an Authenticode-signed and RFC 3161 timestamped final installer executable;
- an attended deployment administrator to provision restricted PostgreSQL roles, TLS, protected secrets, ACLs, and the dedicated non-administrator service account.

`build-installer.ps1 -AllowUnsignedRehearsal` exists only for disposable installation testing. Its output is not authorized for production distribution.

Uninstall removes runtime scheduled tasks but deliberately retains configuration, evidence, logs, backups, audit exports, and immutable releases. Those records require a separate authorized retention or destruction decision.
