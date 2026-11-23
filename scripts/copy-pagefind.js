import fs from "node:fs";
import path from "node:path";

const src = path.resolve("dist/pagefind");
const dest = path.resolve("public/pagefind");

if (fs.existsSync(src)) {
  fs.cpSync(src, dest, { recursive: true, force: true });
}
