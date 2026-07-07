import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  // Auris: bind the dev server on both IPv4 and IPv6 so the Rails-side
  // `vite_javascript_tag` helper (which talks to Vite from Puma via
  // 127.0.0.1) reaches it. Recent Vite versions on macOS default to
  // IPv6-only, which deadlocks the Rails request and the entire
  // Puma worker pool after a few hits.
  server: {
    host: '0.0.0.0',
  },
  resolve: { alias: aliases },
});
