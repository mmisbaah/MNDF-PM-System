# Full-package release integrity

Preparation now produces a version 3 release manifest with SHA-256 hashes for
every file under `.next/standalone`, including dependencies, bundled server code,
public files and browser assets. Only the root manifest and detached signature
are excluded, avoiding circular hashes. Nested files with those names are included.

After dependency links are materialized, the release builder also inventories
the actual packaged `package.json` files into `sbom.cdx.json` using CycloneDX
1.6. The SBOM contains component names, versions, declared licenses, and package
metadata hashes without local filesystem paths. It is created before the release
manifest, is a mandatory inventory entry, and its SHA-256 is repeated in version
10 installer provenance. A missing, replaced, linked-input, or post-generation
modified SBOM therefore blocks integrity verification or installer packaging.

A second required inventory covers **every file in the release's `scripts`
directory**, including `start-production.ps1`, `application-log-redaction.ps1`,
and `validate-production-env.mjs`. These three startup entry points are mandatory.
There are no metadata exclusions in this scripts inventory. Transfer `scripts`
alongside `.next/standalone`, preserving that layout, and do not modify scripts
after signing (including adding Authenticode signatures). Apply any required
PowerShell code signing before preparing and signing the release manifest.

Sign this manifest using the existing offline Ed25519 signing procedure.
Promotion first verifies the signature with the independently pinned key, then
checks the complete file inventory before stopping the application. Added,
missing, modified or duplicate entries fail verification. Symbolic links and
junctions within the package are rejected; prepare a self-contained package of
regular files rather than deploying links to external dependency stores.

Old version 1 and 2 packages must be prepared and signed again. Do not reuse their
detached signatures. Preparation changes the manifest, invalidating any previous
signature even when one remains on disk.

Run `node --test scripts/release-integrity.test.mjs` for disposable-fixture tests.
The suite is configured in both Windows and Linux CI jobs. A real production
build/package/sign/promotion rehearsal is still required before deployment.

Scope: the inventory covers the standalone application tree and release scripts,
not external secrets or configuration. Run the verifier and promotion tooling from a
trusted administrator-controlled location. Release-directory ACLs must prevent
concurrent modification between verification and execution. This check does not
replace those ACLs or independently prove the package matches the Git commit.

The trusted verifier must be the version-3-aware tool, not an unverified tool from
the candidate release. Verification occurs before promotion; this change does
not add a separate signature check at each application restart.

Direct verification: `node scripts/release-integrity.mjs verify <standalone-directory> <release-scripts-directory>`.

## Source provenance

Release candidates must now use `scripts/release-build.ps1` from a clean committed
repository with **no existing `.next` directory**. Existing output is preserved
and rejected, never automatically deleted. Ordinary `npm run build` is still
available for development but does not issue a release receipt.

The release builder checks the commit before and after compilation and inventory
capture, copies static/public assets, creates the version 3 manifest, and issues
`.next/release-build-provenance.json` only after successful verification. This
exclusive-create receipt binds the source commit to the exact manifest SHA-256.
`prepare-standalone.ps1` no longer copies assets or regenerates the manifest: it
requires a matching receipt, current clean commit and verified app/scripts bytes.
Missing receipts, stale commits, changed manifests and altered build output fail.
The local release gate uses this builder for both its code-only and full modes.

Preserve the build receipt with engineering release evidence. It is a local
build-workflow guard, not an independently signed compiler attestation: an actor
able to rewrite the build tooling or receipt remains inside the trusted build
boundary. Offline signing and controlled build custody remain mandatory. The
commit comparison does not detect transient source edits that are reverted during
a build; do not edit or run concurrent builds in a release checkout.

Run `node --test scripts/release-build-provenance.test.mjs`. Windows tests invoke
the actual PowerShell orchestration in a disposable Git repository with a fake
compiler, never the running application. Set `PROVENANCE_TEST_SHELL=pwsh` to test
PowerShell Core. A real clean-commit compilation/signing rehearsal is still needed.

Both the release builder and `prepare-standalone.ps1` require that
`ProjectDirectory` be the repository root and that its Git status contain no
staged, unstaged, untracked, or dirty-submodule changes. It captures `HEAD`, then
checks source status and `HEAD` again before accepting the package. A change
during packaging fails. The checker is read-only and never resets, cleans,
commits, stages, or deletes source files.

Ignored build output such as `.next` is intentionally excluded from Git-status
cleanliness because it is generated by the reviewed build. This control proves
only that tracked/untracked source state is clean at the two checkpoints. It does
not prove reproducible builds, compiler integrity, dependency provenance, or that
an ignored file cannot affect a build. The full-package hashes and signature bind
the resulting artifact after preparation.

Run `scripts/test-release-source-check.ps1` for disposable-repository tests. It
creates commits only inside a uniquely named temporary fixture with hooks and
commit signing disabled, and verifies the checker does not alter fixture source.
The real workspace is not cleaned. Existing pending development changes must be
reviewed and committed through the normal process before a package can be made.
