import { requireAuth } from '../../utils/auth-guard'
import { runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const raw = await runScript('site-list.sh')
  const sites = JSON.parse(raw || '[]')
  return { sites }
})
