# Build 19 purchase validation

Validated 2026-11-17, HST. Final identity: `media.jenny.FuzhouMahjong`; QA identity: `media.jenny.FuzhouMahjong.PurchaseQA19`.

## Passed

- Package tests: 26 total (11 game rules, 7 nearby networking, 8 access policy). Includes free guests joining paid/trial hosts and host expiry before a new deal.
- Native StoreKit tests: 7 on the existing iPhone 17e / iOS 27.3 (`CA5D75B6-6522-490D-AB73-53A20D7E43F0`). Covers the zero-price trial, $4.99 lifetime product, original trial timestamps, exact expiry, automatic entitlement recovery, explicit Restore Purchases, refunds, cancellation, pending/unverified/failing transactions, protected offline license cache before any StoreKit request, save resumption, and finishing a hand after expiry.
- UI tests: 2 each on that phone and the existing iPhone Duo / iOS 27.3 (`62E46C64-B73F-4C60-8BEB-ED9DB5A1A17D`), run sequentially. Covers two free hands, resuming without another charge, hosting offer, trial activation, lifetime purchase, portrait and landscape purchase controls, Restore button reachability, and closing the offer. Wide adaptive sheets can minimize their navigation bar while scrolling; scrolling back reveals Done.
- Generic physical-iPhone Release build before the ID change; signed Debug device build with the final media.jenny identity. Nothing was installed on a physical phone or uploaded.
- App Store Connect app ID `6836200456`: approved name **同桌麻将·福州**, subtitle **福州玩法，离线同玩**, final explicit bundle ID saved. Trial draft `6836203260` and lifetime draft `6836202313` have saved US base price schedules; neither was submitted for review.

No simulator was created, erased, shut down, or deleted by this task. Both existing project devices were reused and retained. QA apps use separate bundle IDs and do not share production saves or license caches.

## Evidence

- `phone-purchase-portrait.png`, `phone-purchase-landscape.png`, `phone-purchase-lifetime-owned.png`
- `duo-purchase-portrait.png`, `duo-purchase-landscape.png`, `duo-purchase-lifetime-owned.png`
- `app-store-info.jpg`, `trial-draft.jpg`, `lifetime-draft.jpg`
- `package-tests.log`, `storekit-tests.log`, `phone-ui-tests.log`, `duo-ui-tests.log`

StoreKitTest uses local simulated purchases; no real Apple account was charged. On a freshly installed QA identity, initialize the local store through the UI flow first, then run the native integration tests. A first native-only run after the ID change could not resolve products; the fresh UI launch established the connection, and subsequent native tests passed. See the test plan and StoreKitProducts.md for the order.

## Remaining acceptance checks

Actual App Store sandbox purchases and refunds, physical-device offline relaunch/restoration, multiple real nearby phones with a purchased host, and the new purchase screen in Duo book/tabletop postures remain untested. Existing build 18 fold evidence is preserved separately. Product localization, review screenshots, distribution availability, app download pricing, agreements, and release metadata remain preparation for a later release; the app and products remain unpublished.
