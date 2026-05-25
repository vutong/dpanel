export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login') return

  const { data } = await useFetch('/api/auth/me', { key: 'auth-me' })
  if (!data.value?.authenticated) {
    return navigateTo('/login')
  }
})
