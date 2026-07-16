import { describe, expect, it } from 'vitest'
import {
  mainTabFromPath,
  mainTabIndex,
  pageViewKey,
} from './route-motion'

describe('route-motion', () => {
  it('maps paths to main tabs', () => {
    expect(mainTabFromPath('/')).toBe('home')
    expect(mainTabFromPath('/dining/7')).toBe('dining')
    expect(mainTabFromPath('/cafe/5')).toBe('cafe')
    expect(mainTabFromPath('/cafe/5/menu')).toBe('cafe')
    expect(mainTabFromPath('/cart')).toBe('cart')
    expect(mainTabFromPath('/order/confirm')).toBe('cart')
    expect(mainTabFromPath('/orders')).toBe('orders')
  })

  it('keeps cafe list and detail under one view key', () => {
    expect(pageViewKey('/cafe/5')).toBe('/cafe/5')
    expect(pageViewKey('/cafe/5/menu')).toBe('/cafe/5')
    expect(pageViewKey('/')).not.toBe(pageViewKey('/dining/7'))
  })

  it('orders tab indices for sliding pill', () => {
    expect(mainTabIndex('home')).toBe(0)
    expect(mainTabIndex('dining')).toBe(1)
    expect(mainTabIndex('cafe')).toBe(2)
    expect(mainTabIndex('cart')).toBe(3)
    expect(mainTabIndex('orders')).toBe(4)
  })
})
