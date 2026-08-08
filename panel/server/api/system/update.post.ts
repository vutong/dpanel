import { requireAuth } from '../../utils/auth-guard'
import {
  beginSystemUpdate,
  runScriptDetached,
  scriptPath,
  stackRoot
} from '../../utils/stack'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const script = join(stackRoot(), 'infra', 'scripts', 'panel-update.sh')
  try {
    await access(script)
  } catch {
    throw createError({
      statusCode: 500,
      statusMessage: 'panel-update.sh not found — run: sudo dpanel update from SSH first'
    })
  }

  // Always force-kill prior job, clear lock + log, then start fresh.
  beginSystemUpdate('Starting dpanel update…')
  runScriptDetached('panel-update.sh', [], {}, undefined, undefined)

  return {
    ok: true,
    accepted: true,
    background: true,
    op: 'update' as const,
    script: scriptPath('panel-update.sh').replace(`${stackRoot()}/`, '')
  }
})
