# Integration checkpoint — 2026-08-31

Status: **incomplete; not deployment approval**.

Verified against the current source workspace:

- Application unit tests: 14 passed (`npm test`).
- Combined Windows deployment regression gate: nine groups passed under Windows
  PowerShell 5.1 with Node 24.19.0. Includes syntax, ACLs, secret-file handling,
  journal recovery guards, source provenance, signatures and package integrity.

Blocked checks:

- `npm run typecheck` failed because Next.js modules/types are missing from the
  source checkout's dependency installation.
- `npm run lint` failed with EPERM while loading the debug dependency.
- The existing non-OneDrive dependency copy has the same lockfile hash but also
  returned EPERM under normal tool access. A whole-workspace elevated lint retry
  did not complete and was stopped. This does not establish a clean lint result.
- Production build, full release packaging, and authenticated browser acceptance
  were not verified in this checkpoint.

Next: prepare a separate non-OneDrive verification checkout containing the current
reviewed source, install dependencies from the frozen lockfile, and run lint,
typecheck, tests and the production build there. Do not reuse or reset the running
application's data/configuration. Review and commit pending source changes before
release packaging, as required by the new provenance gate. Then run the attended
deployment/restoration/browser acceptance process on its designated test host.

No production application was restarted, credentials changed, source changes
committed, or deployment performed by this checkpoint.

## Fresh verification checkout follow-up

Created `C:\dev\PerformanceTracker-verify-20260831-01` from local Git history,
overlaid with the current 293 tracked/untracked source files. Pending changes are
preserved as pending changes; no verification commit was invented. Ignored local
secrets, application data, old dependencies and generated builds were not copied.

Installed all 385 packages using pnpm 10.34.5, `--frozen-lockfile`, a fresh store
at `C:\dev\PerformanceTracker-verify-store-20260831-01`, and copy import mode.
The lockfile remained unchanged (SHA-256
`80D97B9E6901AAF45C36EBAE26AEF1ED913A0BFA7F7E398EE20D9517CF2394CB`).
pnpm reported skipped install scripts for esbuild and unrs-resolver; no blanket
approval of dependency scripts was made.

Results in the fresh checkout:

- TypeScript `--noEmit`: PASS.
- Application unit suite: all 14 tests PASS.
- Next.js 16.2.11 production build (default Turbopack): PASS, including generated
  pages and TypeScript checks. Used a dummy database URL pointing at local port 1;
  no live database credentials were loaded and no server was started.
- Whole-project ESLint: did not complete; stopped after the other checks finished.
  No lint PASS is claimed. Investigating the stalled linter is still required.

Next.js self-hosting guidance informed the build verification. Release packaging
was not attempted because pending source changes intentionally fail the clean-
source guard. This is a verification checkout, not a deployment or a replacement
for the existing localhost workspace.

## Lint and local release-gate follow-up

The earlier lint blocker is superseded by successful full scans in the fresh
checkout: 167 files with zero errors/warnings in 54.7 seconds during diagnosis,
then `npm run lint` with the elapsed-time wrapper completed in 59.9 seconds.
The four wrapper regression tests passed. No dependency or runtime changes were
needed; the earlier multi-minute stall was not reproduced.

The local release gate previously omitted lint despite CI running it. Both local
gate modes now run the wrapper regression and ESLint before other checks. Four
mocked success/failure scenarios passed under Windows PowerShell 5.1 and
PowerShell Core; they verify failure propagation and recorded check status without
running builds, packaging or databases. This regression is included in the combined
Windows deployment gate. The entire combined gate was not rerun for this change.

Pending source review/commit, signed release packaging, and attended
deployment/restoration/authenticated-browser acceptance remain outstanding.
These targeted results do not constitute production release approval.

## Combined safeguard rerun after review fixes

Updated the protected-secret-file fixture to pass its explicitly approved
administrator SIDs to the tightened ACL verifier. All call sites were checked.
The combined deployment regression gate then passed all **11 groups**:

- Windows PowerShell 5.1.26100.9278, Node 24.19.0: PASS,
  2026-08-31 15:36:35–15:37:38 UTC (about 64 seconds).
- PowerShell Core 7.6.4, Node 24.19.0: PASS,
  2026-08-31 15:36:43–15:37:19 UTC (about 36 seconds).
  `PROVENANCE_TEST_SHELL=pwsh` selected Core for nested build-fixture tests too.

Coverage includes database cleanup ownership, lint failure propagation, stop
guards, deployment journaling, approved-principal ACL verification, protected
secret creation, environment serialization, clean source checks, build provenance,
full app/scripts inventory, signing and configuration validation. These runs used
disposable fixtures and did not deploy, modify live data, or change production
permissions. A real clean-commit build and attended release rehearsal remain
outstanding; this is not production approval.

## Isolated clean-commit release rehearsal

Rehearsal checkout: `C:\dev\PerformanceTracker-rehearsal-20260831-01`.
Rehearsal-only commit: `50d0e9f11263163287ad7ea52acd6d9b7e871eee`.
The original repository was not staged or committed. A direct OneDrive clone
failed reading a Git object; the existing non-OneDrive verification checkout
provided the same base commit instead. Current source files were overlaid and
verified by SHA-256 before committing the isolated snapshot.

- Fresh frozen-lockfile pnpm 10.34.5 installation: PASS, 385 packages from the
  local store using copy import mode. No lockfile changes or dependency build
  script approval.
- Unit tests: PASS, 14/14.
- Next.js 16.2.11 production compilation, TypeScript and 42-page generation:
  PASS, using a dummy nonconnecting database URL.
- Guarded release build: BLOCKED after compilation. Next.js generated an
  untracked `next-env.d.ts`; the post-build clean-source guard rejected it.
  No provenance receipt was issued, and package preparation was not run.
- Lint: PASS, exit 0. The wrapper reported 3910 seconds with a large jump
  between progress messages; this is not a reliable active-runtime benchmark.

Next action: define the Git policy for generated `next-env.d.ts`, add regression
coverage, and repeat the guarded build from a new clean snapshot. Do not bypass
the source-cleanliness guard or reuse this incomplete build as a signed release.
No live database, service, signing key or deployment was changed.

## Generated-file fix and second release rehearsal

The root-only `/next-env.d.ts` Git ignore rule now covers Next.js-generated
declarations. The release source guard itself is unchanged. Regression fixtures
use the actual project ignore policy and verify that generated root declarations
are allowed, but nested declarations, other untracked files, and staged/unstaged
source edits are rejected. The build fixture now emits the generated declaration.
Source-policy checks and both provenance tests passed under Windows PowerShell
5.1 and PowerShell Core.

Fresh checkout: `C:\dev\PerformanceTracker-rehearsal-20260831-02`.
Rehearsal-only commit: `d232b3bcd4cf5d6505435877e7220135148d3938`.
Fresh frozen-lockfile installation: PASS (385 packages, pnpm 10.34.5).
Unit tests: PASS (14/14). Production compilation, TypeScript, and generation of
42 pages: PASS. The post-build source-cleanliness check now passes, and Git status
remains clean. Original source was not committed; live services were untouched.

Packaging remains BLOCKED by a separate, correctly enforced integrity check:
`.next/standalone/.next/node_modules/pg-63e85fc611dc39f8` is a junction targeting
the checkout's `node_modules/.pnpm/pg@8.20.0/node_modules/pg`, outside the standalone
package. No provenance receipt was issued and package preparation did not run.
The next task is safe, self-contained dependency materialization for standalone
packaging, with containment and tamper regression tests. Do not permit arbitrary
links or sign this incomplete package. Lint was not rerun for this narrow fix.

## Self-contained dependency packaging

Release builds now require a fresh hoisted dependency installation (frozen pnpm
lockfile, copy import mode). A staging materializer permits dependency aliases
only within the standalone output or this checkout's dependencies, rejects
escaping/dangling/cyclic/non-dependency links, and preserves raw compiler output.
The existing final-package no-links policy is unchanged. Documentation in
`RELEASE_GATE.md` records the install command and trusted/exclusive-input boundary.

Fresh checkout: `C:\dev\PerformanceTracker-rehearsal-20260831-03`.
Rehearsal-only commit: `16652b5bf8b978d7e502bbeca887b2d45bca9d0d`.

- Frozen hoisted install: PASS, pnpm 10.34.5; 389 installed entries from 385
  cached packages, no lockfile changes or dependency script approval.
- Combined safeguard suite: all 11 groups PASS under Windows PowerShell 5.1,
  including 12 Node tests; 2026-08-31 17:38:22–17:39:28 UTC.
- Targeted materialization/provenance suite: all 8 tests PASS with PowerShell
  Core selected for nested orchestration. Six new tests cover copied runtime
  dependencies, tampering, unsafe links and existing-output preservation.
- Production compilation, TypeScript and 42-page generation: PASS.
- Materialization: PASS, one dependency junction replaced with regular files.
- Full integrity manifest creation, provenance recording and final package
  preparation: PASS. Git status remained clean after build.
- Targeted ESLint on the three changed JavaScript files: PASS, exit 0.
- Package-only runtime import probe: PASS for the generated server imports
  (`next`, `next/dist/server/lib/start-server`), `pg`, `react`, and the traced
  database alias, with 491 file resolutions constrained to the package. An
  initial broader probe of `next/server` was rejected because that unused facade
  is not part of this traced artifact. This is not full HTTP/DB acceptance.

Provenance manifest SHA-256:
`5fd5886c22d2f6a0f05259d8dd7213a2e7ef83a4e97de124af023b444b9e2c8e`.
Receipt completed at 2026-08-31 17:44:04 UTC. The artifact is an unsigned rehearsal
snapshot, not an approved production release. No original-repository commit,
live service, database, signing key or deployment was changed. Next: attended
release signing/staging rehearsal and runtime acceptance with approved inputs.

## Disposable signing and isolated staging rehearsal

Staging root: `C:\dev\PerformanceTracker-signing-stage-20260831-01`.
Artifact: `releases\16652b5-rehearsal`, sourced from the clean rehearsal commit
`16652b5bf8b978d7e502bbeca887b2d45bca9d0d`. Only the final standalone artifact,
release scripts and provenance receipt were transferred, not build dependencies
or raw compiler output. The staging root ACL was restricted to the operating
identity, SYSTEM and local Administrators before disposable key creation.

PASS: original provenance, transferred full inventory/provenance, disposable
Ed25519 signing and verification, changed-manifest rejection, substituted-key
rejection, changed-startup-helper rejection, and final restored artifact checks.
The generated passphrase was confined to the signing process environment. The
disposable encrypted private key was removed afterward; public key, signature,
negative-test evidence and `evidence/signing-result.json` remain available.

Rehearsal-only public-key fingerprint:
`10e49b9827505c6738f12bfd269e79e931c89f5d50766c5b66fbd368e062dfc7`.
This locally generated trust value is not production key custody or approval.

BLOCKED: actual `promote-release.ps1 -Initialize` ceremony, including its pinned
fingerprint negative test. It stopped at the elevation prerequisite because the
tool session is not an administrator token. No junction or journal was created,
and no scheduled task, live service or database was touched. Do not bypass this
guard. An operator must run `tmp/initialize-signing-stage-rehearsal.ps1` from an
Administrator PowerShell window. The helper targets only the isolated root and
uses Initialize mode, which does not start/stop application services. Actual
promotion, rollback, runtime acceptance and production signing remain untested.

## Elevated pointer ceremony and hardened runtime follow-up

The first isolated signed artifact (`16652b5`) was initialized successfully after
attended UAC approval. An incorrect pinned key fingerprint was rejected without
creating a pointer; the valid signature and full inventory then produced only the
isolated `current` junction and matching `STARTED`/`INITIALIZED` journal records.
Operation ID: `b6965546ef8f446288d3f64117dc31a9`. No service was changed.

Runtime probing found and fixed two issues: `poweredByHeader: false` now suppresses
Next.js disclosure, and unavailable health dependencies return HTTP 503. Both have
regression tests in the combined safeguard gate.

Hardened checkout: `C:\dev\PerformanceTracker-rehearsal-20260901-04`.
Rehearsal-only commit: `0184a78a5b667e377600036c4081444330ba3506`.

- Combined safeguard suite: all 11 groups PASS, including 14 Node regressions;
  2026-09-01 00:43:01–00:44:11 UTC.
- Application unit tests: PASS, 14/14. Targeted lint: PASS.
- Clean guarded build: PASS (compile, TypeScript, 42 pages, materialization,
  manifest, provenance and preparation).
- Loopback runtime: root 200 with correct branding, anonymous internal API 401,
  dummy-database health 503, and no `X-Powered-By` or `Server` header. Stopped.

The hardened artifact was signed and reverified under
`C:\dev\PerformanceTracker-signing-stage-20260901-02`; tamper tests passed and the
disposable private key was removed. Fingerprint:
`a9dd52c9e979955a09b20859d27ba4ba8e6bc7cf9ca058fce8291c06cada387e`.
Its UAC request for pointer initialization was canceled, so no second pointer or
journal exists. No bypass was attempted.

Original source remains intentionally uncommitted. Production remains blocked on
a reviewed source commit, real offline signing custody, protected configuration
and database, TLS, scheduled service identity, ACLs, backup/restore evidence and
attended acceptance. Rehearsal success is not production approval.
