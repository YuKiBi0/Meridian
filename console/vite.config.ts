import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Built with a relative base so the same files work under any
// MERIDIAN_BASE_PATH. In dev the console is served at /meridian/ and API
// calls are proxied to a local meridian-server.
export default defineConfig(({ command }) => ({
  base: command === 'build' ? './' : '/meridian/',
  plugins: [vue()],
  build: { outDir: 'dist', emptyOutDir: true, target: 'es2020' },
  server: {
    proxy: {
      '/meridian/api': {
        target: process.env.MERIDIAN_DEV_SERVER ?? 'http://127.0.0.1:18090',
        changeOrigin: true,
      },
    },
  },
}))
