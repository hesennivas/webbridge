import { defineConfig } from 'vite'

// zero-framework static landing. vite handles the woff2, css minify/hashing and
// the tiny interaction bundle. output is a fully static /dist served by caddy on railway.
export default defineConfig({
  build: {
    target: 'es2020',
    assetsInlineLimit: 0,
  },
  server: { port: 5174, host: true },
})
