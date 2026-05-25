import { requireAuth } from '../../utils/auth-guard'
import { runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const raw = await runScript('db-list.sh')
  const databases = JSON.parse(raw || '[]')
  return { databases }
})
