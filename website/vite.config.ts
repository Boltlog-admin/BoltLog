import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// GitHub Pages project site: https://<org>.github.io/<repo>/ — set VITE_BASE_PATH=/RepoName/ in CI
const base = process.env.VITE_BASE_PATH?.replace(/\/?$/, "/") || "./";

export default defineConfig({
  plugins: [react()],
  base,
});
