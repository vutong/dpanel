import { requireAuth } from '../../utils/auth-guard'
import {
  runScriptDetached,
  scriptPath,
  stackRoot,
  systemUpdateStatusPath,
  writeSystemUpdateStatus,
  type SystemUpdateStatus
} from '../../utils/stack'
import { access, readFile } from 'node:fs/promises'
import { join } from 'node:path'

async function readSystemUpdateStatus(): Promise<SystemUpdateStatus> {
  try {
    const raw = await readFile(systemUpdateStatusPath(), 'utf8')
    return JSON.parse(raw) as SystemUpdateStatus
  } catch {
    return { status: 'none' }
  }
}

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

  const current = await readSystemUpdateStatus()
  if (current.status === 'running') {
    return {
      ok: true,
      accepted: false,
      alreadyRunning: true,
      background: true,
      op: 'update' as const
    }
  }

  writeSystemUpdateStatus('running', 'Starting dpanel update…')
  runScriptDetached('panel-update.sh', [], {}, undefined, undefined)

  return {
    ok: true,
    accepted: true,
    background: true,
    op: 'update' as const,
    script: scriptPath('panel-update.sh').replace(`${stackRoot()}/`, '')
  }
})
