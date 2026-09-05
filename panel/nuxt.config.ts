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
    },
    // Upload FM is 64 MB (nginx client_max_body_size). Other panel APIs are tiny JSON.
    // Nitro has no per-route body limit; handler still 413s over 64 MB.
    bodySizeLimit: 65 * 1024 * 1024
  },
  routeRules: {
    '/login': { ssr: false }
  },
  app: {
    head: {
      title: 'dpanel',
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1' }],
      script: [
        {
          innerHTML:
            "(function(){try{var t=localStorage.getItem('dpanel-theme');document.documentElement.setAttribute('data-theme',t==='light'?'light':'dark')}catch(e){document.documentElement.setAttribute('data-theme','dark')}})();",
          tagPosition: 'head',
          key: 'dpanel-theme-init'
        }
      ]
    }
  }
})
