import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";

// A separate process keeps the heartbeat responsive even during synchronous lint work.
export function runWithProgress(command, args, {
  intervalMs = 10_000,
  report = (message) => console.error(message),
} = {}) {
  const started = performance.now();
  const elapsed = () => `${((performance.now() - started) / 1000).toFixed(1)}s`;
  report("[lint] Starting ESLint; elapsed-time updates every 10 seconds.");
  return new Promise((resolveResult) => {
    const child = spawn(command, args, { stdio: "inherit", shell: false });
    let launchError;
    let interrupted;
    const interrupt = (signal) => {
      interrupted = signal;
      child.kill(signal);
    };
    const onInterrupt = () => interrupt("SIGINT");
    const onTerminate = () => interrupt("SIGTERM");
    process.on("SIGINT", onInterrupt);
    process.on("SIGTERM", onTerminate);
    const timer = setInterval(() => {
      report(`[lint] ${elapsed()} elapsed — ESLint is still running (not a completion percentage).`);
    }, intervalMs);
    child.once("error", (error) => { launchError = error; });
    child.once("close", (code, signal) => {
      clearInterval(timer);
      process.off("SIGINT", onInterrupt);
      process.off("SIGTERM", onTerminate);
      const stoppedBy = interrupted || signal;
      const exitCode = launchError ? 2 : stoppedBy ? (stoppedBy === "SIGINT" ? 130 : 143) : (code ?? 2);
      if (launchError) report(`[lint] Could not start ESLint: ${launchError.message}`);
      report(`[lint] ${stoppedBy ? "Interrupted" : exitCode === 0 ? "Completed successfully" : "Failed"} after ${elapsed()} (exit ${exitCode}).`);
      resolveResult(exitCode);
    });
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const require = createRequire(import.meta.url);
    const eslintCli = join(dirname(require.resolve("eslint/package.json")), "bin", "eslint.js");
    const args = process.argv.slice(2);
    process.exitCode = await runWithProgress(process.execPath, [eslintCli, ...(args.length ? args : ["."])]);
  } catch (error) {
    console.error(`[lint] Unable to load ESLint: ${error.message}`);
    process.exitCode = 2;
  }
}
