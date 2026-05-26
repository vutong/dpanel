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
