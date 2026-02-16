import { createServer } from "node:http";
import { query as claudeQuery } from "@anthropic-ai/claude-agent-sdk";
import { Codex } from "@openai/codex-sdk";

// ─────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────
const PORT = parseInt(process.env.PROXY_PORT || "11435", 10);

// Model registry: model alias → { provider, apiModel }
const MODEL_REGISTRY = {
  // ── Claude models (via claude-agent-sdk — OAuth auto)
  "claude-sonnet":         { provider: "anthropic", apiModel: "claude-sonnet-4-5-20250929" },
  "claude-opus":           { provider: "anthropic", apiModel: "claude-opus-4-5-20251101" },
  "claude-haiku":          { provider: "anthropic", apiModel: "claude-haiku-4-5-20251001" },
  // ── Embedding model (required by AppFlowy for AI Search)
  "nomic-embed-text":      { provider: "embedding", apiModel: "nomic-embed-text" },
  // ── OpenAI Codex models (via codex-sdk — OAuth auto)
  "gpt-5.3-codex":         { provider: "openai", apiModel: "gpt-5.3-codex" },
  "gpt-5.3-codex-spark":   { provider: "openai", apiModel: "gpt-5.3-codex-spark" },
  "gpt-5.2-codex":         { provider: "openai", apiModel: "gpt-5.2-codex" },
  "gpt-5.2":               { provider: "openai", apiModel: "gpt-5.2" },
  "gpt-5.1-codex-max":     { provider: "openai", apiModel: "gpt-5.1-codex-max" },
  "gpt-5.1-codex":         { provider: "openai", apiModel: "gpt-5.1-codex" },
  "gpt-5.1":               { provider: "openai", apiModel: "gpt-5.1" },
  "gpt-5-codex":           { provider: "openai", apiModel: "gpt-5-codex" },
  "gpt-5-codex-mini":      { provider: "openai", apiModel: "gpt-5-codex-mini" },
  "gpt-5":                 { provider: "openai", apiModel: "gpt-5" },
  "o3":                    { provider: "openai", apiModel: "o3" },
  "o4-mini":               { provider: "openai", apiModel: "o4-mini" },
  "gpt-4.1":               { provider: "openai", apiModel: "gpt-4.1" },
  "gpt-4o":                { provider: "openai", apiModel: "gpt-4o" },
  "gpt-4o-mini":           { provider: "openai", apiModel: "gpt-4o-mini" },
};

// ─────────────────────────────────────────────
// OpenAI via codex-sdk (OAuth auto-managed)
// ─────────────────────────────────────────────
const codexClient = new Codex();

// ─────────────────────────────────────────────
// Ollama API: GET /api/tags
// ─────────────────────────────────────────────
function getAvailableModels() {
  const models = [];
  const now = new Date().toISOString();
  for (const [name, info] of Object.entries(MODEL_REGISTRY)) {
    // All providers always available (SDKs manage auth);
    models.push({
      name: `${name}:latest`,
      model: `${name}:latest`,
      modified_at: now,
      size: 0,
      digest: `sha256:${Buffer.from(name).toString("hex").padEnd(64, "0")}`,
      details: {
        parent_model: "",
        format: "api",
        family: info.provider,
        families: [info.provider],
        parameter_size: "cloud",
        quantization_level: "none",
      },
    });
  }
  return { models };
}

// ─────────────────────────────────────────────
// Claude via claude-agent-sdk (OAuth auto)
// ─────────────────────────────────────────────
async function callClaudeSDK(messages, model) {
  const parts = [];
  let systemPrompt = "";
  for (const msg of messages) {
    if (msg.role === "system") systemPrompt = msg.content;
    else if (msg.role === "user") parts.push(`User: ${msg.content}`);
    else if (msg.role === "assistant") parts.push(`Assistant: ${msg.content}`);
  }
  const prompt = systemPrompt ? `${systemPrompt}\n\n${parts.join("\n")}` : parts.join("\n");

  let fullResult = "";
  for await (const msg of claudeQuery({
    prompt,
    options: { model, allowedTools: [], maxTurns: 1 },
  })) {
    if (msg.result) fullResult = msg.result;
  }
  return fullResult;
}

// ─────────────────────────────────────────────
// OpenAI via codex-sdk (OAuth auto)
// ─────────────────────────────────────────────
async function callCodexSDK(messages) {
  const parts = [];
  for (const msg of messages) {
    if (msg.role === "system") parts.push(`System: ${msg.content}`);
    else if (msg.role === "user") parts.push(`User: ${msg.content}`);
    else if (msg.role === "assistant") parts.push(`Assistant: ${msg.content}`);
  }
  const prompt = parts.join("\n");
  const thread = codexClient.startThread({ skipGitRepoCheck: true });
  const turn = await thread.run(prompt);
  return turn.finalResponse || "";
}

// ─────────────────────────────────────────────
// Request Handlers
// ─────────────────────────────────────────────
function parseBody(req) {
  if (req._parsedBody) return Promise.resolve(req._parsedBody);
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => { try { const p = data ? JSON.parse(data) : {}; req._parsedBody = p; resolve(p); } catch (e) { reject(e); } });
    req.on("error", reject);
  });
}

function resolveModel(rawName) {
  const name = rawName.replace(/:latest$/, "");
  const entry = MODEL_REGISTRY[name];
  return entry ? { name, ...entry } : null;
}

async function handleChat(req, res) {
  const body = await parseBody(req);
  const model = resolveModel(body.model || "");
  if (!model) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: `Unknown model: ${body.model}. Available: ${Object.keys(MODEL_REGISTRY).join(", ")}` }));
    return;
  }

  const messages = body.messages || [];
  const stream = body.stream !== false;
  const options = body.options || {};

  console.log(`[${model.provider}] ${model.apiModel} | ${stream ? "stream" : "sync"} | ${messages.length} msgs`);

  try {
    // ── Get result from the appropriate SDK
    let result;
    if (model.provider === "anthropic") {
      result = await callClaudeSDK(messages, model.apiModel);
    } else if (model.provider === "openai") {
      result = await callCodexSDK(messages);
    } else {
      result = "";
    }

    // ── Send response in Ollama format
    if (stream) {
      res.writeHead(200, { "Content-Type": "application/x-ndjson", "Transfer-Encoding": "chunked" });
      const chunkSize = 12;
      for (let i = 0; i < result.length; i += chunkSize) {
        res.write(JSON.stringify({ model: body.model, created_at: new Date().toISOString(), message: { role: "assistant", content: result.slice(i, i + chunkSize) }, done: false }) + "\n");
      }
      res.write(JSON.stringify({ model: body.model, created_at: new Date().toISOString(), message: { role: "assistant", content: "" }, done: true, done_reason: "stop" }) + "\n");
      res.end();
    } else {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ model: body.model, created_at: new Date().toISOString(), message: { role: "assistant", content: result }, done: true, done_reason: "stop" }));
    }
  } catch (e) {
    console.error(`[${model.provider}] Failed:`, e.message);
    if (!res.headersSent) res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: e.message }));
  }
}

async function handleGenerate(req, res) {
  const body = await parseBody(req);
  body.messages = [{ role: "user", content: body.prompt || "" }];
  if (body.system) body.messages.unshift({ role: "system", content: body.system });
  req._parsedBody = body;
  return handleChat(req, res);
}

// ─────────────────────────────────────────────
// Server
// ─────────────────────────────────────────────
const server = createServer(async (req, res) => {
  const path = new URL(req.url, `http://localhost:${PORT}`).pathname;
  try {
    if (path === "/" && req.method === "GET") { res.writeHead(200, { "Content-Type": "text/plain" }); res.end("Ollama is running"); return; }
    if (path === "/api/version" && req.method === "GET") { res.writeHead(200, { "Content-Type": "application/json" }); res.end(JSON.stringify({ version: "0.6.2" })); return; }
    if (path === "/api/tags" && req.method === "GET") { res.writeHead(200, { "Content-Type": "application/json" }); res.end(JSON.stringify(getAvailableModels())); return; }
    if (path === "/api/chat" && req.method === "POST") { await handleChat(req, res); return; }
    if (path === "/api/generate" && req.method === "POST") { await handleGenerate(req, res); return; }
    if (path === "/api/show" && req.method === "POST") {
      const body = await parseBody(req);
      const model = resolveModel(body.name || body.model || "");
      if (!model) { res.writeHead(404); res.end(JSON.stringify({ error: "model not found" })); return; }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ modelfile: `# ${model.name} via ${model.provider}`, parameters: "", template: "", details: { parent_model: "", format: "api", family: model.provider } }));
      return;
    }
    if (path === "/api/embeddings" && req.method === "POST") {
      const body = await parseBody(req);
      // Generate a deterministic pseudo-embedding from input text (768 dimensions like nomic-embed-text)
      const text = body.prompt || body.input || "";
      const dim = 768;
      const embedding = Array.from({ length: dim }, (_, i) => {
        let h = 0;
        for (let j = 0; j < text.length; j++) h = ((h << 5) - h + text.charCodeAt(j) + i) | 0;
        return (h % 10000) / 10000;
      });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ embedding }));
      return;
    }
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: `Not found: ${req.method} ${path}` }));
  } catch (e) {
    console.error("[Server] Error:", e);
    if (!res.headersSent) res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: e.message }));
  }
});

// ─────────────────────────────────────────────
// Startup
// ─────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`\n  AppFlowy AI Proxy (Ollama-compatible)`);
  console.log(`  http://localhost:${PORT}\n`);
  console.log(`  Providers:`);
  console.log(`  | anthropic | claude-agent-sdk (OAuth auto) | ready`);
  console.log(`  | openai    | codex-sdk (OAuth auto)        | ready`);
  console.log();
  const available = Object.entries(MODEL_REGISTRY);
  console.log(`  Models (${available.length}):`);
  for (const [name, info] of available) console.log(`  ${info.provider === "anthropic" ? "●" : "○"} ${name} -> ${info.apiModel}`);
  console.log(`\n  AppFlowy: Settings > AI > Local AI > URL = http://localhost:${PORT}\n`);
});
