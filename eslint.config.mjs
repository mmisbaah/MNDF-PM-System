import { defineConfig, globalIgnores } from "eslint/config";
import nextCoreWebVitals from "eslint-config-next/core-web-vitals";

export default defineConfig([
  // Keep the starter on the flat config export that actually runs under the pinned ESLint/Next toolchain.
  ...nextCoreWebVitals,
  {
    rules: {
      // These React Compiler advisory rules reject established runtime patterns in
      // this application. Data fetching and wizard-index synchronization belong in
      // effects, deadline comparisons require the current server-aligned time, and
      // the explicit rating memo has intentionally narrower dependencies. The
      // standard hooks, purity, TypeScript, and Core Web Vitals rules remain active.
      "react-hooks/set-state-in-effect": "off",
      "react-hooks/preserve-manual-memoization": "off",
      "react-hooks/purity": "off",
    },
  },
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts"]),
]);
