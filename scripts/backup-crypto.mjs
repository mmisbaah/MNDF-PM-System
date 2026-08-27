import { createCipheriv, createDecipheriv, createHmac, generateKeyPairSync, privateDecrypt, publicEncrypt, randomBytes, timingSafeEqual } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { access, open, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { pipeline } from "node:stream/promises";

const MAGIC = Buffer.from("PTBKv1\0\0", "binary");
const IV_BYTES = 12;
const TAG_BYTES = 16;

function usage() {
  throw new Error("Usage: backup-crypto.mjs keygen|encrypt|decrypt|hmac|verify-hmac [arguments]");
}

async function assertAbsent(path) {
  try {
    await access(path);
    throw new Error(`Refusing to overwrite existing file: ${path}`);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

async function keygen(publicKeyPath, privateKeyPath) {
  if (!publicKeyPath || !privateKeyPath) usage();
  const passphrase = process.env.BACKUP_PRIVATE_KEY_PASSPHRASE;
  if (!passphrase || passphrase.length < 16) {
    throw new Error("BACKUP_PRIVATE_KEY_PASSPHRASE must contain at least 16 characters");
  }
  await assertAbsent(publicKeyPath);
  await assertAbsent(privateKeyPath);
  const pair = generateKeyPairSync("rsa", {
    modulusLength: 3072,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem", cipher: "aes-256-cbc", passphrase },
  });
  await writeFile(publicKeyPath, pair.publicKey, { mode: 0o644 });
  await writeFile(privateKeyPath, pair.privateKey, { mode: 0o600 });
}

async function encrypt(inputPath, outputPath, publicKeyPath) {
  if (!inputPath || !outputPath || !publicKeyPath) usage();
  await assertAbsent(outputPath);
  const publicKey = await readFile(publicKeyPath, "utf8");
  const aesKey = randomBytes(32);
  const iv = randomBytes(IV_BYTES);
  const wrappedKey = publicEncrypt({ key: publicKey, oaepHash: "sha256" }, aesKey);
  if (wrappedKey.length > 65535) throw new Error("Wrapped key is unexpectedly large");
  const keyLength = Buffer.alloc(2);
  keyLength.writeUInt16BE(wrappedKey.length);
  const header = Buffer.concat([MAGIC, keyLength, iv, wrappedKey]);
  const temporaryPath = `${outputPath}.partial`;
  await rm(temporaryPath, { force: true });
  const cipher = createCipheriv("aes-256-gcm", aesKey, iv);
  const output = createWriteStream(temporaryPath, { flags: "wx" });
  output.write(header);
  try {
    await pipeline(createReadStream(inputPath), cipher, output, { end: false });
    await new Promise((resolve, reject) => output.write(cipher.getAuthTag(), (error) => error ? reject(error) : resolve()));
    await new Promise((resolve, reject) => output.end((error) => error ? reject(error) : resolve()));
    await rename(temporaryPath, outputPath);
  } catch (error) {
    output.destroy();
    await rm(temporaryPath, { force: true });
    throw error;
  }
}

async function decrypt(inputPath, outputPath, privateKeyPath) {
  if (!inputPath || !outputPath || !privateKeyPath) usage();
  await assertAbsent(outputPath);
  const passphrase = process.env.BACKUP_PRIVATE_KEY_PASSPHRASE;
  if (!passphrase) throw new Error("BACKUP_PRIVATE_KEY_PASSPHRASE is required");
  const privateKey = await readFile(privateKeyPath, "utf8");
  const handle = await open(inputPath, "r");
  try {
    const prefix = Buffer.alloc(MAGIC.length + 2 + IV_BYTES);
    const prefixRead = await handle.read(prefix, 0, prefix.length, 0);
    if (prefixRead.bytesRead !== prefix.length || !prefix.subarray(0, MAGIC.length).equals(MAGIC)) {
      throw new Error("Unsupported or damaged encrypted backup header");
    }
    const wrappedLength = prefix.readUInt16BE(MAGIC.length);
    const iv = prefix.subarray(MAGIC.length + 2);
    const wrappedKey = Buffer.alloc(wrappedLength);
    const wrappedRead = await handle.read(wrappedKey, 0, wrappedLength, prefix.length);
    if (wrappedRead.bytesRead !== wrappedLength) throw new Error("Truncated encrypted backup header");
    const file = await stat(inputPath);
    const headerLength = prefix.length + wrappedLength;
    if (file.size <= headerLength + TAG_BYTES) throw new Error("Encrypted backup has no payload");
    const tag = Buffer.alloc(TAG_BYTES);
    await handle.read(tag, 0, TAG_BYTES, file.size - TAG_BYTES);
    const aesKey = privateDecrypt({ key: privateKey, passphrase, oaepHash: "sha256" }, wrappedKey);
    const decipher = createDecipheriv("aes-256-gcm", aesKey, iv);
    decipher.setAuthTag(tag);
    const temporaryPath = `${outputPath}.partial`;
    await rm(temporaryPath, { force: true });
    try {
      await pipeline(
        createReadStream(inputPath, { start: headerLength, end: file.size - TAG_BYTES - 1 }),
        decipher,
        createWriteStream(temporaryPath, { flags: "wx" }),
      );
      await rename(temporaryPath, outputPath);
    } catch (error) {
      await rm(temporaryPath, { force: true });
      throw new Error(`Backup authentication or decryption failed: ${error.message}`);
    }
  } finally {
    await handle.close();
  }
}

async function hmac(inputPath, outputPath) {
  if (!inputPath || !outputPath) usage();
  const secret = process.env.AUDIT_EXPORT_HMAC_KEY;
  if (!secret || secret.length < 32) throw new Error("AUDIT_EXPORT_HMAC_KEY must contain at least 32 characters");
  await assertAbsent(outputPath);
  const digest = createHmac("sha256", secret).update(await readFile(inputPath)).digest("hex");
  await writeFile(outputPath, `${digest}\n`, { mode: 0o600 });
}

async function verifyHmac(inputPath, signaturePath) {
  if (!inputPath || !signaturePath) usage();
  const secret = process.env.AUDIT_EXPORT_HMAC_KEY;
  if (!secret || secret.length < 32) throw new Error("AUDIT_EXPORT_HMAC_KEY must contain at least 32 characters");
  const expected = Buffer.from((await readFile(signaturePath, "utf8")).trim(), "hex");
  const actual = Buffer.from(createHmac("sha256", secret).update(await readFile(inputPath)).digest("hex"), "hex");
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) throw new Error("Audit manifest HMAC verification failed");
}

const [command, ...args] = process.argv.slice(2);
if (command === "keygen") await keygen(...args);
else if (command === "encrypt") await encrypt(...args);
else if (command === "decrypt") await decrypt(...args);
else if (command === "hmac") await hmac(...args);
else if (command === "verify-hmac") await verifyHmac(...args);
else usage();
