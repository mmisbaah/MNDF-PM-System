# Software supply-chain controls

The lockfile is authoritative. Production and CI installations must use `pnpm install --frozen-lockfile`; unreviewed lockfile regeneration is prohibited.

Every pull request and release-candidate push runs accessibility policy, browser-regression syntax validation, ESLint, TypeScript, automated tests, a complete dependency vulnerability audit, and a production build. High or critical dependency findings—including development and build tooling—block the code gate. CodeQL performs extended JavaScript/TypeScript analysis on changes, release-candidate pushes, and weekly.

Dependabot proposes weekly npm updates and monthly GitHub Actions updates. Each proposal requires human review, successful automated gates, and regression testing proportional to the affected component. Major-version updates remain separate and must include migration notes. Do not enable automatic merging or direct production deployment.

All external GitHub Actions references are pinned to full 40-character commit
hashes. A readable release comment accompanies each hash, while Dependabot
remains responsible for proposing reviewed updates. The deployment regression
gate rejects a mutable tag, branch, shortened hash, or malformed external action
reference before release. Verify proposed hashes against the action's official
repository and reviewed release before merging an update.

Before release, the Technical Operator records the commit, lockfile hash, successful workflow run, open security findings, accepted-risk owner and expiry, and deployed artifact hash. Secrets, environment files, evidence, database exports, and backup keys must never be uploaded as workflow artifacts.
