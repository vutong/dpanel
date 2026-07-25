import bcrypt from 'bcryptjs'
import { requireAuth } from '../../utils/auth-guard'
import { readAuth, updateAuthPassword } from '../../utils/stack'

async function verifyPassword(password: string, passwordHash: string): Promise<boolean> {
  const hash = passwordHash.startsWith('$2') ? passwordHash : `$2y${passwordHash.slice(3)}`
  return bcrypt.compare(password, hash.replace(/^\$2y\$/, '$2a$'))
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ currentPassword?: string; newPassword?: string }>(event)
  const currentPassword = body.currentPassword || ''
  const newPassword = body.newPassword || ''

  if (!currentPassword || !newPassword) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Current password and new password are required'
    })
  }

  if (newPassword.length < 8) {
    throw createError({
      statusCode: 400,
      statusMessage: 'New password must be at least 8 characters'
    })
  }

  if (currentPassword === newPassword) {
    throw createError({
      statusCode: 400,
      statusMessage: 'New password must be different from the current password'
    })
  }

  let auth: { email: string; passwordHash: string }
  try {
    auth = await readAuth()
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'Auth not configured — run install.sh' })
  }

  const ok = await verifyPassword(currentPassword, auth.passwordHash)
  if (!ok) {
    throw createError({ statusCode: 401, statusMessage: 'Current password is incorrect' })
  }

  const passwordHash = await bcrypt.hash(newPassword, 10)
  try {
    await updateAuthPassword(passwordHash)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'Failed to update password' })
  }

  return { ok: true }
})
