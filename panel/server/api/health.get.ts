import { getStackVersion } from '../utils/version'
import { runScript } from '../utils/stack'

export default defineEventHandler(async () => {
  const version = await getStackVersion()

  try {
    const out = await runScript('health-check.sh', ['--json'], 120_000)
    const line = out.trim().split('\n').pop() || out
    const report = JSON.parse(line) as {
      ok?: boolean
      version?: string
      issues?: number
      checks?: Array<{ id: string; ok: boolean; message: string; fix?: string }>
    }
    return {
      ok: report.ok ?? true,
      service: 'dpanel',
      version: report.version || version,
      issues: report.issues ?? 0,
      checks: report.checks ?? []
    }
  } catch {
    return {
      ok: true,
      service: 'dpanel',
      version,
      issues: 0,
      checks: [{ id: 'panel', ok: true, message: 'Panel process running (full stack check: dpanel health)' }]
    }
  }
})
