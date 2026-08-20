import { requireAuth } from '../../../utils/auth-guard'
import { startSecurityInstall } from '../../../utils/security-install'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  return startSecurityInstall('fail2ban')
})
