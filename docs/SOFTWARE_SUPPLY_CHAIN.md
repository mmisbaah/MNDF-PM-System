# Software supply-chain controls

The lockfile is authoritative. Production and CI installations must use `pnpm install --frozen-lockfile`; unreviewed lockfile regeneration is prohibited.

Every pull request and release-candidate push runs accessibility policy, ESLint, TypeScript, automated tests, a production-only dependency vulnerability audit, and a production build. High or critical production dependency findings block the code gate. CodeQL performs extended JavaScript/TypeScript analysis on changes, release-candidate pushes, and weekly.

Dependabot proposes weekly npm updates and monthly GitHub Actions updates. Each proposal requires human review, successful automated gates, and regression testing proportional to the affected component. Major-version updates remain separate and must include migration notes. Do not enable automatic merging or direct production deployment.

Before release, the Technical Operator records the commit, lockfile hash, successful workflow run, open security findings, accepted-risk owner and expiry, and deployed artifact hash. Secrets, environment files, evidence, database exports, and backup keys must never be uploaded as workflow artifacts.
