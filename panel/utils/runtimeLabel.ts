/** User-facing label for site runtime (`node` | `php`). */
export function runtimeLabel(runtime: string | null | undefined): string {
  const r = (runtime || '').trim().toLowerCase()
  if (r === 'node') return 'Node SSR'
  if (r === 'php') return 'PHP'
  return runtime || '—'
}
