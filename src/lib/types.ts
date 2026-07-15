/** Types shaped like skill API responses (fmt.py / eliga-api.sh). */

export type ShopType = 'CAFE' | 'CAFETERIA' | string

export interface Shop {
  shopId: number
  name: string
  type: ShopType
  open: boolean
}

export interface CafeCategory {
  id: number
  name: string
  mobileUseYn: boolean
  goodsCount: number
}

export interface CafeMenuItem {
  displayId: number
  goodsId: number | null
  name: string
  category: string
  price: number
  soldOut: boolean
  description: string | null
  calorie: number | null
  nutrition: string | null
  label: string | null
  displayName: string
}

export interface OptionMenu {
  menuId: number
  name: string
  price: number
}

export interface GoodsOption {
  optionId: number
  name: string
  multiSelect: boolean
  menus: OptionMenu[]
}

export interface GoodsVariant {
  goodsId: number
  name: string
  displayName: string
  price: number
  soldOut: boolean
  description: string | null
  calorie: number | null
  nutrition: string | null
  options: GoodsOption[]
}

export interface MenuDetail {
  displayId: number
  shopId: number | null
  label: string | null
  variants: GoodsVariant[]
}

export interface DiningMenuItem {
  name: string
  calorie: number | null
  nutrition: string
  information: string
}

export interface DiningCourse {
  name: string
  price: number
  menus: DiningMenuItem[]
  soldOut: boolean
  congestion: string | null
  origin: string
}

export interface DiningPeriod {
  time: string
  startTime: string
  endTime: string
  courses: DiningCourse[]
}

export interface CartOptionView {
  option: string
  value: string
}

export interface CartItem {
  cartItemId: number
  goodsId: number
  name: string
  qty: number
  price: number
  options: CartOptionView[]
}

export interface Cart {
  cartId: number | null
  shopId?: number
  items: CartItem[]
}

export interface PaymentReason {
  id: number
  reason: string
}

/** Selected option for cart-add (simplified skill shape). */
export interface SelectedOption {
  optionId: number
  menuId?: number
  menuIds?: number[]
}

export interface CartAddItem {
  goodsId: number
  qty: number
  options: SelectedOption[]
}

export interface OrderItemPayload {
  goodsId: number
  goodsQty: number
  salesPrice: number
  unitPrice: number
  goodsCartItemId: number
  goodsOrderItemOptions: unknown[]
}

export interface OrderPayload {
  deviceType: 'MOBILE' | 'PC'
  orderType: 'AUTO'
  payType: 'INTERNAL'
  brandCode: string
  shopId: number
  cartId: number
  totalUnitPrice: number
  totalSalesPrice: number
  totalUsedPoint: number
  goodsOrderType: 'SHOP_PICKUP'
  paymentReasonId: number
  orderItems: OrderItemPayload[]
}

export interface AuthTokens {
  accessToken: string
  refreshToken: string
  tokenType?: string
}
