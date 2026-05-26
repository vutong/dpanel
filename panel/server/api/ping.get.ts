/** Fast liveness probe — must not call health-check.sh (avoids recursion from CLI health). */
export default defineEventHandler(() => ({
  ok: true,
  service: 'dpanel'
}))
