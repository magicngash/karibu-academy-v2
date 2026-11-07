import { readFile, writeFile } from "node:fs/promises";

async function loadDotEnv() {
  try {
    const contents = await readFile(".env", "utf8");
    for (const line of contents.split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
      if (!match || process.env[match[1]]) continue;
      process.env[match[1]] = match[2].replace(/^(["'])(.*)\1$/, "$2");
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

await loadDotEnv();

const url = process.env.KARIBU_SUPABASE_URL || "https://pwvyadoeecujktuosetr.supabase.co";
const anonKey = process.env.KARIBU_SUPABASE_ANON_KEY;

if (!anonKey) {
  throw new Error("Missing KARIBU_SUPABASE_ANON_KEY. Set it in Netlify environment variables.");
}

const runtimeConfig = `window.KARIBU_SUPABASE_URL = ${JSON.stringify(url)};\nwindow.KARIBU_SUPABASE_ANON_KEY = ${JSON.stringify(anonKey)};\n`;
await writeFile("runtime-config.js", runtimeConfig, "utf8");
console.log("Generated runtime-config.js");
