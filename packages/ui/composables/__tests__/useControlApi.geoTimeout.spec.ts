import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useControlApi } from '../useControlApi'

describe('control API slow GEO downloads', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    ;(globalThis as any).window = {
      location: { origin: 'http://nas.example:8080' },
    }
    // Exercise the real ky client against a download that takes 24 seconds,
    // matching the three-file download observed on the NAS.
    vi.spyOn(globalThis, 'fetch').mockImplementation((input) => {
      const request = input as Request
      return new Promise<Response>((resolve, reject) => {
        const timer = setTimeout(() => {
          resolve(
            new Response(
              JSON.stringify({
                ok: true,
                files: ['geoip.dat', 'geosite.dat', 'country.mmdb'],
              }),
              { headers: { 'content-type': 'application/json' } },
            ),
          )
        }, 24_000)
        request.signal.addEventListener(
          'abort',
          () => {
            clearTimeout(timer)
            reject(request.signal.reason)
          },
          { once: true },
        )
      })
    })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
    delete (globalThis as any).window
  })

  it('waits for a GEO refresh that exceeds the ordinary request timeout', async () => {
    const outcome = useControlApi()
      .updateGeoAssets()
      .then(
        (value) => ({ value }),
        (error) => ({ error }),
      )
    await vi.advanceTimersByTimeAsync(24_000)
    expect(await outcome).toEqual({
      value: { ok: true, files: ['geoip.dat', 'geosite.dat', 'country.mmdb'] },
    })
  })

  it('still times out an ordinary status request after 15 seconds', async () => {
    const outcome = useControlApi()
      .getKernelStatus()
      .then(
        () => 'unexpected success',
        (error) => error.name,
      )
    await vi.advanceTimersByTimeAsync(24_000)
    expect(await outcome).toBe('TimeoutError')
  })
})
