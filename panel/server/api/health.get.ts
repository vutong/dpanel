import { getStackVersion } from '../utils/version'

export default defineEventHandler(async () => ({
  ok: true,
  service: 'dpanel',
  version: await getStackVersion()
}))
