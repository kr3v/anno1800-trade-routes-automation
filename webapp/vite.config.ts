import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  publicDir: 'static', // Serve static assets from 'static' folder
  base: './', // For GitHub Pages compatibility
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
