# StoreKit products

App bundle: `media.jenny.FuzhouMahjong`, team `5736QK4NZX`. Build 19 introduces StoreKit 2 purchasing without subscriptions or a backend.

| Product ID | Type | Reference name | US base price |
| --- | --- | --- | --- |
| `media.jenny.FuzhouMahjong.trial14` | Non-consumable | 14-day Trial | $0.00 |
| `media.jenny.FuzhouMahjong.lifetime` | Non-consumable | Lifetime Full Unlock | $4.99 |

The app must remain free to download. Do not change either product ID after shipping. Family Sharing is not enabled by this implementation or local catalog. Trial access is measured from the verified original purchase timestamp; the earliest timestamp remembered locally prevents a restore from extending it.

The trial screen discloses the duration, the features available during the trial, what remains free afterward, no automatic billing, and the current localized lifetime price before activation. Apple documents time-based non-subscription trials in [App Review guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).

## App Store Connect preparation

The draft app record is [同桌麻将·福州](https://appstoreconnect.apple.com/apps/6836200456/distribution/info), Apple ID `6836200456`, with subtitle **福州玩法，离线同玩**. The explicit bundle ID `media.jenny.FuzhouMahjong` is registered to Jenny Media LLC and saved on this record. The original internal SKU `xyz.xcv58.FuzhouMahjong` is immutable in App Store Connect; it does not control signing, purchases, or the installed app identity. No build has been uploaded to this record.

Both non-consumable drafts exist in App Store Connect, with their US base price schedules saved: [14-day Trial, $0.00](https://appstoreconnect.apple.com/apps/6836200456/distribution/iaps/6836203260) and [Lifetime Full Unlock, $4.99](https://appstoreconnect.apple.com/apps/6836200456/distribution/iaps/6836202313). Both remain **Prepare for Submission**. Finish their localized metadata, review screenshot, and country availability before review. The app's download price and availability also still need to be configured; keep the download free. Before release, verify the paid-app agreement/tax/banking status and exercise the real sandbox and Restore Purchases on physical devices. Product creation is preparation; uploading a build, submitting for review, and publishing are separate steps.

The new bundle identity installs separately from earlier local `xyz.xcv58.FuzhouMahjong` builds. Existing saved games remain in the earlier app's container and are not imported automatically. This change does not uninstall the earlier app.

## Local validation

The regular **FuzhouMahjong** scheme uses live StoreKit. Only **FuzhouMahjongPurchases** and its **Purchases** test plan attach `PurchaseTests/FuzhouMahjong.storekit`. Never attach the local catalog to a release archive.

Run package tests with `swift test`. On a fresh simulator or after changing the bundle ID, run the UI test target first so the app registers its local StoreKit test connection, then run the native integration target. The test plan lists UI tests first; explicit `-only-testing:FuzhouPurchaseFlowTests` and `-only-testing:FuzhouPurchasesTests` invocations also work. For local StoreKit integration and UI tests, reuse an existing idle project QA simulator, reserve its lock, and pass its UUID explicitly. Run one destination at a time:

```sh
xcodebuild -project FuzhouMahjong.xcodeproj \
  -scheme FuzhouMahjongPurchases -testPlan Purchases \
  -destination 'platform=iOS Simulator,id=<existing-project-QA-UUID>' \
  -derivedDataPath .derived-data \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  VALIDATION_BUNDLE_SUFFIX=.PurchaseQA19 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=5736QK4NZX test
```

The suffix isolates validation from the installed app's saves and license cache. Simulator signing is required to test the Keychain cache. Test products and transactions are local, with purchase dialogs disabled by StoreKitTest; no real account is charged.

Policy tests cover exact expiry, local-day allowance, saved hands, clock rollback, migration, and free guests. Native tests exercise verified StoreKit transactions, restoration, cancellation, pending and failed/unverified purchases, refunds, Keychain reuse before any network request, and continuation of an active hand after expiry. UI tests cover the free allowance and purchase screen in portrait and landscape.

Physical offline purchase caching, the real App Store sandbox, family account behavior, and multiple nearby phones remain release acceptance checks. Local StoreKit and encrypted loopback tests cannot establish radio behavior on a cruise.
