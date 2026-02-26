import { defineConfig } from 'vite';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        terms: resolve(__dirname, 'terms.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        support: resolve(__dirname, 'support.html'),
        developer: resolve(__dirname, 'developer.html'),
        docs: resolve(__dirname, 'docs.html'),
        success: resolve(__dirname, 'success-v1-x8fk2m9s7q5p4r3w.html'),
        cancel: resolve(__dirname, 'cancel.html'),
        affiliate: resolve(__dirname, 'affiliate.html'),
        millionmails: resolve(__dirname, 'millionmails.html'),
      },
    },
  },
});

