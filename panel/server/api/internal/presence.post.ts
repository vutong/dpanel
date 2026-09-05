import { readBody } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { mergePresenceSections, type CacheSectionKey } from '../../utils/cache-meta'

const ALLOWED_SECTIONS: CacheSectionKey[] = ['dashboard', 'databases', 'websites', 'settings']

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const body = await readBody<{ sections?: string[]; domain?: string }>(event).catch(() => ({}))
  const sections = (Array.isArray(body?.sections) ? body.sections : [])
    .map((s) => String(s).trim())
    .filter((s): s is CacheSectionKey => ALLOWED_SECTIONS.includes(s as CacheSectionKey))

  if (!sections.length) {
    throw createError({ statusCode: 400, statusMessage: 'At least one valid section is required' })
  }

  const domain = String(body?.domain || '')
    .trim()
    .toLowerCase()

  const meta = await mergePresenceSections(sections, domain || undefined)
  return { ok: true, sections: meta.sections }
})
