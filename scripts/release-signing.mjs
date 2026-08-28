import { createHash, createPrivateKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";

const [command, ...args] = process.argv.slice(2);
const passphrase = process.env.RELEASE_SIGNING_KEY_PASSPHRASE ?? "";
const digest = (data) => createHash("sha256").update(data).digest("hex");

async function mustNotExist(path) {
  try { await access(path); throw new Error(`Refusing to overwrite existing file: ${path}`); } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

function signatureEnvelope(manifest, privateKey) {
  return {
    format: "performance-tracker-release-signature-v1",
    algorithm: "Ed25519",
    manifestSha256: digest(manifest),
    signature: sign(null, manifest, privateKey).toString("base64"),
  };
}

function verifyEnvelope(manifest, envelope, publicKey) {
  if (envelope.format !== "performance-tracker-release-signature-v1" || envelope.algorithm !== "Ed25519") return false;
  if (!/^[0-9a-f]{64}$/.test(envelope.manifestSha256) || envelope.manifestSha256 !== digest(manifest)) return false;
  return verify(null, manifest, publicKey, Buffer.from(envelope.signature ?? "", "base64"));
}

if (command === "keygen") {
  const [privatePath, publicPath] = args;
  if (!privatePath || !publicPath) throw new Error("Usage: keygen <encrypted-private-key> <public-key>");
  if (passphrase.length < 20) throw new Error("RELEASE_SIGNING_KEY_PASSPHRASE must contain at least 20 characters");
  await mustNotExist(privatePath); await mustNotExist(publicPath);
  const keys = generateKeyPairSync("ed25519", {
    privateKeyEncoding: { type: "pkcs8", format: "pem", cipher: "aes-256-cbc", passphrase },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  await writeFile(privatePath, keys.privateKey, { mode: 0o600 });
  await writeFile(publicPath, keys.publicKey, { mode: 0o644 });
  console.log("Release signing key pair created. Move the encrypted private key to offline release custody.");
} else if (command === "sign") {
  const [manifestPath, privatePath, signaturePath] = args;
  if (!manifestPath || !privatePath || !signaturePath) throw new Error("Usage: sign <manifest> <encrypted-private-key> <signature>");
  if (passphrase.length < 20) throw new Error("RELEASE_SIGNING_KEY_PASSPHRASE is required");
  await mustNotExist(signaturePath);
  const manifest = await readFile(manifestPath);
  const privateKey = createPrivateKey({ key: await readFile(privatePath), format: "pem", passphrase });
  await writeFile(signaturePath, `${JSON.stringify(signatureEnvelope(manifest, privateKey), null, 2)}\n`, { mode: 0o644 });
  console.log(`Signed manifest SHA-256 ${digest(manifest)}`);
} else if (command === "verify") {
  const [manifestPath, signaturePath, publicPath] = args;
  if (!manifestPath || !signaturePath || !publicPath) throw new Error("Usage: verify <manifest> <signature> <public-key>");
  const manifest = await readFile(manifestPath);
  const envelope = JSON.parse(await readFile(signaturePath, "utf8"));
  const publicKey = await readFile(publicPath);
  if (!verifyEnvelope(manifest, envelope, publicKey)) throw new Error("Release signature verification failed");
  console.log(`Release signature verified for manifest SHA-256 ${digest(manifest)}`);
} else if (command === "selftest") {
  const keys = generateKeyPairSync("ed25519");
  const manifest = Buffer.from('{"commit":"0123456789abcdef"}');
  const envelope = signatureEnvelope(manifest, keys.privateKey);
  if (!verifyEnvelope(manifest, envelope, keys.publicKey)) throw new Error("Valid release signature was rejected");
  if (verifyEnvelope(Buffer.concat([manifest, Buffer.from("x")]), envelope, keys.publicKey)) throw new Error("Tampered release manifest was accepted");
  console.log("Release signing self-test passed.");
} else {
  throw new Error("Command must be keygen, sign, verify, or selftest");
}
