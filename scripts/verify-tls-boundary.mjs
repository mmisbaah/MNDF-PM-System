import tls from "node:tls";

const publicUrl = new URL(process.env.PRODUCTION_PUBLIC_URL ?? "");
if (publicUrl.protocol !== "https:") throw new Error("PRODUCTION_PUBLIC_URL must use https://");
if (publicUrl.username || publicUrl.password || publicUrl.search || publicUrl.hash) throw new Error("PRODUCTION_PUBLIC_URL must not contain credentials, a query, or a fragment");

const minimumCertificateDays = Number(process.env.TLS_MIN_CERTIFICATE_DAYS ?? "14");
if (!Number.isInteger(minimumCertificateDays) || minimumCertificateDays < 1 || minimumCertificateDays > 90) {
  throw new Error("TLS_MIN_CERTIFICATE_DAYS must be an integer between 1 and 90");
}

const timeoutMs = 10_000;
const controller = () => AbortSignal.timeout(timeoutMs);
const httpsResponse = await fetch(publicUrl, { redirect: "manual", signal: controller() });
if (httpsResponse.status < 200 || httpsResponse.status >= 400) throw new Error(`HTTPS endpoint returned ${httpsResponse.status}`);
const hsts = httpsResponse.headers.get("strict-transport-security") ?? "";
const hstsMaxAge = hsts.match(/max-age=(\d+)/i);
if (!hstsMaxAge || Number(hstsMaxAge[1]) < 31_536_000) throw new Error("HSTS max-age must be at least one year");
if (httpsResponse.headers.has("server")) throw new Error("The public proxy must suppress the Server response header");

const internalUrl = new URL("/api/internal/tls-boundary-probe", publicUrl);
const internalResponse = await fetch(internalUrl, { redirect: "manual", signal: controller() });
if (internalResponse.status !== 404) throw new Error(`Internal route boundary returned ${internalResponse.status}, expected 404`);

const httpUrl = new URL(publicUrl);
httpUrl.protocol = "http:";
httpUrl.port = process.env.PRODUCTION_HTTP_PORT ?? "80";
const redirectResponse = await fetch(httpUrl, { redirect: "manual", signal: controller() });
if (![301, 302, 307, 308].includes(redirectResponse.status)) throw new Error(`HTTP endpoint did not redirect (status ${redirectResponse.status})`);
const location = redirectResponse.headers.get("location");
if (!location) throw new Error("HTTP redirect has no Location header");
const redirectTarget = new URL(location, httpUrl);
if (redirectTarget.protocol !== "https:" || redirectTarget.hostname !== publicUrl.hostname) throw new Error("HTTP redirect does not target the configured HTTPS host");

const certificate = await new Promise((resolve, reject) => {
  const socket = tls.connect({
    host: publicUrl.hostname,
    port: Number(publicUrl.port || 443),
    servername: publicUrl.hostname,
    rejectUnauthorized: true,
    minVersion: "TLSv1.2",
    timeout: timeoutMs,
  });
  socket.once("secureConnect", () => {
    const peer = socket.getPeerCertificate();
    const protocol = socket.getProtocol();
    socket.end();
    resolve({ peer, protocol });
  });
  socket.once("timeout", () => socket.destroy(new Error("TLS connection timed out")));
  socket.once("error", reject);
});

if (!certificate.peer?.valid_to) throw new Error("TLS peer did not provide a certificate expiry date");
const remainingDays = (Date.parse(certificate.peer.valid_to) - Date.now()) / 86_400_000;
if (remainingDays < minimumCertificateDays) throw new Error(`TLS certificate expires in ${remainingDays.toFixed(1)} days`);

console.log(JSON.stringify({
  status: "PASS",
  publicUrl: publicUrl.origin,
  tlsProtocol: certificate.protocol,
  certificateExpiresAt: new Date(certificate.peer.valid_to).toISOString(),
  certificateRemainingDays: Number(remainingDays.toFixed(1)),
  hsts,
}));
