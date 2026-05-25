export default defineNuxtConfig({
  compatibilityDate: '2025-05-25',
  devtools: { enabled: false },
  css: ['~/assets/css/main.css'],
  ssr: true,
  runtimeConfig: {
    stackRoot: process.env.STACK_ROOT || '/opt/stack',
    sessionSecret: process.env.PANEL_SESSION_SECRET || 'change-me-in-production',
    public: {
      panelDomain: process.env.PANEL_DOMAIN || 'panel.local'
    }
  },
  nitro: {
    experimental: {
      wasm: false
    }
  },
  app: {
    head: {
      title: 'dpanel',
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1' }]
    }
  }
})
