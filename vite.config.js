import { defineConfig } from 'vite';
import { resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  appType: 'mpa',
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
        error: resolve(__dirname, '404.html'),
      },
    },
  },
  plugins: [
    {
      name: '404-fallback',
      configureServer(server) {
        server.middlewares.use((req, res, next) => {
          const url = req.url.split('?')[0];
          // Simple check for missing routes
          if (url !== '/' && !url.includes('.') && !url.startsWith('/@') && !url.startsWith('/node_modules')) {
            const knownRoutes = ['/terms', '/privacy', '/support', '/developer', '/docs', '/success', '/cancel', '/affiliate', '/millionmails'];
            if (!knownRoutes.includes(url)) {
              req.url = '/404.html';
            }
          }
          next();
        });
      },
    },
  ],
});
