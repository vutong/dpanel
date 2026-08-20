import { requireAuth } from '../../../utils/auth-guard'
import { fetchHostSecurityStatus } from '../../../utils/host-security'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const install = recordSecurityInstallEventIfNeeded('clamav')
    const status = await fetchHostSecurityStatus()
    return {
      ok: true,
      installed: status.clamav?.installed ?? false,
      daemonActive: status.clamav?.daemonActive ?? false,
      freshclamActive: status.clamav?.freshclamActive ?? false,
      signatureDate: status.clamav?.signatureDate ?? null,
      installStatus: install.status,
      installMessage: install.message ?? ''
    }
  } catch (e: unknown) {
    const install = resolveSecurityInstallStatus('clamav')
    if (install.status === 'running') {
      return {
        ok: true,
        installed: false,
        daemonActive: false,
        freshclamActive: false,
        signatureDate: null,
        installStatus: install.status,
        installMessage: install.message ?? ''
      }
    }
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
