
const crypto = require("crypto");

function sha256Hex(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}
function hmac(key, data) {
  return crypto.createHmac("sha256", key).update(data).digest();
}
function getConfig() {
  const accountId = process.env.R2_ACCOUNT_ID;
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  const bucket = process.env.R2_BUCKET || "fahmny-videos";
  if (!accountId || !accessKeyId || !secretAccessKey) {
    throw new Error("R2 secrets are not configured. Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY.");
  }
  return { accountId, accessKeyId, secretAccessKey, bucket };
}
function endpoint(accountId) {
  return `https://${accountId}.r2.cloudflarestorage.com`;
}
function signingKey(secret, date, region="auto", service="s3") {
  const kDate = hmac(Buffer.from("AWS4" + secret, "utf8"), date);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}
function encodePath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}
function canonicalQuery(params) {
  return Object.keys(params).sort().map(k => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`).join("&");
}
function canonicalUri(bucket, key) {
  return `/${encodePath(bucket)}/${encodePath(key)}`;
}

function presignedUrl({ method, key, expiresSeconds=900, contentType }) {
  const { accountId, accessKeyId, secretAccessKey, bucket } = getConfig();
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "").replace("Z", "Z");
  const dateStamp = amzDate.slice(0, 8);
  const region = "auto";
  const service = "s3";
  const credential = `${accessKeyId}/${dateStamp}/${region}/${service}/aws4_request`;
  const headers = { host };
  const signedHeaders = "host";
  const params = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": credential,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(Math.min(Math.max(expiresSeconds, 1), 604800)),
    "X-Amz-SignedHeaders": signedHeaders
  };
  const canonicalRequest = [
    method,
    canonicalUri(bucket, key),
    canonicalQuery(params),
    `host:${host}\n`,
    signedHeaders,
    "UNSIGNED-PAYLOAD"
  ].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${sha256Hex(canonicalRequest)}`;
  const signature = hmac(signingKey(secretAccessKey, dateStamp, region, service), stringToSign).toString("hex");
  params["X-Amz-Signature"] = signature;
  const url = `${endpoint(accountId)}${canonicalUri(bucket, key)}?${canonicalQuery(params)}`;
  return { url, contentType: contentType || undefined, expiresAtMs: Date.now() + Number(params["X-Amz-Expires"]) * 1000 };
}

async function putObject(key, buffer, contentType="application/octet-stream") {
  const { accountId, accessKeyId, secretAccessKey, bucket } = getConfig();
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "").replace("Z", "Z");
  const dateStamp = amzDate.slice(0, 8);
  const region = "auto", service = "s3";
  const payloadHash = sha256Hex(buffer);
  const canonicalHeaders = `content-type:${contentType}\nhost:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date";
  const canonical = [
    "PUT", canonicalUri(bucket,key), "",
    canonicalHeaders,
    signedHeaders,
    payloadHash
  ].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${sha256Hex(canonical)}`;
  const signature = hmac(signingKey(secretAccessKey,dateStamp,region,service), stringToSign).toString("hex");
  const auth = `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const res = await fetch(`${endpoint(accountId)}${canonicalUri(bucket,key)}`, {
    method:"PUT",
    headers: { Host: host, "x-amz-content-sha256": payloadHash, "x-amz-date": amzDate, Authorization: auth, "Content-Type": contentType },
    body: buffer
  });
  if (!res.ok) throw new Error(`R2 upload failed: ${res.status} ${await res.text()}`);
}

async function deleteObject(key) {
  const { accountId, accessKeyId, secretAccessKey, bucket } = getConfig();
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  const region = "auto", service = "s3";
  const payloadHash = sha256Hex("");
  const canonicalHeaders = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = "host;x-amz-content-sha256;x-amz-date";
  const canonical = ["DELETE", canonicalUri(bucket, key), "", canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${sha256Hex(canonical)}`;
  const signature = hmac(signingKey(secretAccessKey, dateStamp, region, service), stringToSign).toString("hex");
  const auth = `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const res = await fetch(`${endpoint(accountId)}${canonicalUri(bucket, key)}`, {
    method: "DELETE",
    headers: { Host: host, "x-amz-content-sha256": payloadHash, "x-amz-date": amzDate, Authorization: auth },
  });
  if (!res.ok && res.status !== 404) throw new Error(`R2 delete failed: ${res.status}`);
}

module.exports = { presignedUrl, putObject, deleteObject, getConfig };
