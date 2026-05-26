import { getStackVersion } from '../utils/version'

export default defineEventHandler(async () => {
  const version = await getStackVersion()
  return {
    ok: true,
    service: 'dpanel',
    version,
    message: 'Panel process running (full stack: dpanel health)'
  }
})
