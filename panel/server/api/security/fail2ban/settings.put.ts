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
      throw createError({ statusCode: 400, statusMessage: 'resetJail is required' })
    }
    const settings = resetJailToDefault(jail)
    try {
      const raw = await runScript('host-fail2ban-config-apply.sh', [], 120_000)
      const applied = parseScriptJson<{ ok: boolean; error?: string; warnings?: string[] }>(raw)
      if (!applied.ok) {
        throw new Error(applied.error || 'Apply failed')
      }
      return { ok: true, settings, warnings: applied.warnings ?? [] }
    } catch (e: unknown) {
      throw createError({
        statusCode: 500,
        statusMessage: scriptErrorMessage(e)
      })
    }
  }

  const validated = validateFail2banSettings(body)
  if (!validated.ok) {
    throw createError({ statusCode: 400, statusMessage: validated.error })
  }

  writeFail2banSettings(validated.settings)

  try {
    const raw = await runScript('host-fail2ban-config-apply.sh', [], 120_000)
    const applied = parseScriptJson<{ ok: boolean; error?: string; warnings?: string[] }>(raw)
    if (!applied.ok) {
      throw new Error(applied.error || 'Apply failed')
    }
    return { ok: true, settings: validated.settings, warnings: applied.warnings ?? [] }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
