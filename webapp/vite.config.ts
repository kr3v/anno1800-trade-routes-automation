import { defineConfig } from 'vite';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Support versioned deployments via environment variable
// e.g., BASE_PATH=/anno1800-trade-routes-automation/v0.0.1/
const basePath = process.env.BASE_PATH || '/anno1800-trade-routes-automation/';

export default defineConfig({
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  publicDir: 'static', // Serve static assets from 'static' folder
  base: basePath, // For GitHub Pages compatibility
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
