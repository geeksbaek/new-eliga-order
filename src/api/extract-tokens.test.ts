import { describe, expect, it } from 'vitest'
import { extractTokensFromSignInBody } from './client'

describe('extractTokensFromSignInBody', () => {
  it('reads content.accessToken (api-reference shape)', () => {
    expect(
      extractTokensFromSignInBody({
        content: {
          accessToken: 'aaa',
          refreshToken: 'bbb',
          tokenType: 'Bearer',
        },
      }),
    ).toEqual({
      accessToken: 'aaa',
      refreshToken: 'bbb',
      tokenType: 'Bearer',
    })
  })

  it('returns null for cookie-only success body', () => {
    expect(extractTokensFromSignInBody({ content: true })).toBeNull()
    expect(extractTokensFromSignInBody({})).toBeNull()
    expect(extractTokensFromSignInBody(null)).toBeNull()
  })

  it('accepts snake_case and nested token', () => {
    expect(
      extractTokensFromSignInBody({
        content: { access_token: 'x', refresh_token: 'y' },
      })?.accessToken,
    ).toBe('x')
    expect(
      extractTokensFromSignInBody({
        content: { token: { accessToken: 'z' } },
      })?.accessToken,
    ).toBe('z')
  })
})
