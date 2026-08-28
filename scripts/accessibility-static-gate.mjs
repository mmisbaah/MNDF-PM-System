import { readFile } from "node:fs/promises";

const layout = await readFile(new URL("../src/app/layout.tsx", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/app/globals.css", import.meta.url), "utf8");
const workspace = await readFile(new URL("../src/components/PilotWorkspace.tsx", import.meta.url), "utf8");

const checks = [
  ["document language", /<html lang="en">/.test(layout)],
  ["keyboard skip link", /href="#main-content"/.test(layout) && /id="main-content"/.test(layout)],
  ["user zoom remains available", !/userScalable:\s*false/.test(layout) && !/maximumScale:\s*1/.test(layout)],
  ["48px interactive targets", /min-height:\s*48px/.test(styles) && /min-width:\s*48px/.test(styles)],
  ["visible keyboard focus", /:focus-visible/.test(styles)],
  ["reduced motion support", /prefers-reduced-motion:\s*reduce/.test(styles)],
  ["high contrast focus support", /forced-colors:\s*active/.test(styles)],
  ["workspace navigation landmark", /<nav\s/.test(workspace)],
  ["icon controls have accessible names", /aria-label="Refresh"/.test(workspace)],
];

const failures = checks.filter(([, passed]) => !passed);
for (const [name, passed] of checks) console.log(`${passed ? "PASS" : "FAIL"} ${name}`);
if (failures.length) {
  console.error(`Accessibility gate failed: ${failures.map(([name]) => name).join(", ")}`);
  process.exit(1);
}
