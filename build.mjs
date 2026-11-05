import { writeFile } from "node:fs/promises";

const url = process.env.KARIBU_SUPABASE_URL || "https://pwvyadoeecujktuosetr.supabase.co";
const anonKey = process.env.KARIBU_SUPABASE_ANON_KEY;

if (!anonKey) {
  throw new Error("Missing KARIBU_SUPABASE_ANON_KEY. Set it in Netlify environment variables.");
}

const runtimeConfig = `window.KARIBU_SUPABASE_URL = ${JSON.stringify(url)};\nwindow.KARIBU_SUPABASE_ANON_KEY = ${JSON.stringify(anonKey)};\n`;
await writeFile("runtime-config.js", runtimeConfig, "utf8");
console.log("Generated runtime-config.js");
