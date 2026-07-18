# Native system integrations

## Remote order notifications

The app registers with APNs at launch and persists the hexadecimal device token in the shared app group. The next sign-in sends that value through the backend's existing `fcmToken` field. The field name is legacy; the provider must treat tokens from this iOS client as APNs device tokens, or exchange them for FCM registration tokens after Firebase configuration is added.

Supported order payload:

```json
{
  "aps": {
    "alert": {
      "title": "픽업 준비 완료",
      "body": "주문한 메뉴를 픽업해 주세요."
    },
    "sound": "default",
    "content-available": 1
  },
  "orderId": 314,
  "orderNo": "A-0314",
  "status": "WAITING_FOR_PICKUP"
}
```

The client also accepts `orderID`, `orderStatus`, or a nested `order` object. Notification taps open the order-history tab. Silent order payloads update an active Live Activity.

## Live Activity push updates

Each order Live Activity requests an ActivityKit push token and stores it in the app group under `live-activity.push-tokens.v1`. A production provider still needs an authenticated endpoint to upload and revoke those per-activity tokens. Until that endpoint exists, the app updates activities after order creation, foreground refreshes, remote app notifications, and scheduled background refreshes.

## Background refresh

`com.leeari95.NewEligaOrder.refresh` refreshes shops, carts, widgets, Spotlight entities, and active order activities. The app requests a one-minute earliest begin date while an order is active and 30 minutes otherwise, but iOS decides the actual execution time. Guaranteed real-time order transitions still require APNs or ActivityKit push updates.

## Device-only order monitoring

After a successful order, the app persists the active order in the shared app group and polls the official order-status API every 8 seconds while foregrounded. When the app enters the background, it requests finite background execution time and polls every 10 seconds until iOS expires that time. It also requests a `BGAppRefreshTask` with a one-minute earliest begin date while an order remains active.

Detected phase changes update the Live Activity and create a local notification. Completed, cancelled, and orders older than six hours are removed automatically. This is a best-effort fallback: iOS chooses whether and when to run `BGAppRefreshTask`, and force-quitting the app stops device-only monitoring until the next launch.

## Spotlight and Siri

Authenticated refreshes cache and donate all cafe menus plus today's dining meals as `IndexedEntity` values. Opening a cafe result navigates to that menu. Opening a dining result reconstructs and presents the selected meal detail rather than only opening the dining tab.
