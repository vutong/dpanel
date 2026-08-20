import { requireAuth } from '../../../utils/auth-guard'
import {
  readFail2banSettings,
  resetJailToDefault,
  validateFail2banSettings,
  writeFail2banSettings
} from '../../../utils/fail2ban-settings'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody(event)

  if (body?.resetJail) {
    const jail = String(body.resetJail).trim()
    if (!jail) {
      return { ok: false, error: 'resetJail is required' }
    }
    const settings = resetJailToDefault(jail)
    try {
      const raw = await runScript('host-fail2ban-config-apply.sh', [], 120_000)
      const applied = parseScriptJson<{ ok: boolean; error?: string; warnings?: string[] }>(raw)
      if (!applied.ok) {
        return { ok: false, error: applied.error || 'Apply failed', settings, warnings: [] }
      }
      return { ok: true, settings, warnings: applied.warnings ?? [] }
    } catch (e: unknown) {
      return {
        ok: false,
        error: scriptErrorMessage(e),
        settings,
        warnings: []
      }
    }
  }

  const validated = validateFail2banSettings(body)
  if (!validated.ok) {
    return { ok: false, error: validated.error }
  }

  writeFail2banSettings(validated.settings)

  try {
    const raw = await runScript('host-fail2ban-config-apply.sh', [], 120_000)
    const applied = parseScriptJson<{ ok: boolean; error?: string; warnings?: string[] }>(raw)
    if (!applied.ok) {
      return {
        ok: false,
        error: applied.error || 'Apply failed',
        settings: validated.settings,
        warnings: []
      }
    }
    return { ok: true, settings: validated.settings, warnings: applied.warnings ?? [] }
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e),
      settings: validated.settings,
      warnings: []
    }
  }
})
