# Build 18 Duo layout QA

Tested 2026-11-17, Xcode 27.3 / iOS Simulator 27.3. The QA app uses `xyz.xcv58.FuzhouMahjong.Duo18QA`, separate from production saves. No gameplay or purchase logic changed for Duo support.

## Reused devices

- iPhone Duo: `62E46C64-B73F-4C60-8BEB-ED9DB5A1A17D`.
- iPhone 17e: `CA5D75B6-6522-490D-AB73-53A20D7E43F0`.
- Both devices were idle before reservation. Tests and interaction runs were sequential. No simulator was created, erased, shut down, or deleted. Both existing devices are retained. Temporary QA app installations and session reservations were removed after capture; the Duo returned to its closed upright pose, the phone to portrait, and text size to its original Large setting.

## Checks

- Duo closed outer display: portrait and landscape; fully open inner display: portrait, reverse portrait, and landscape. Reverse portrait was additionally confirmed as `Portrait Upside Down` in the simulator display metadata. The outer display retains the system restriction on upside-down portrait, documented in [UINavigationController](https://developer.apple.com/documentation/uikit/uinavigationcontroller). The app declares all four orientations for the inner display.
- Partially folded: book and tabletop, including opposite rotations, using Device Hub's native pose controls and actual active reserved regions.
- Active match survived folding/unfolding. A manually reordered tile remained in the same order across book, tabletop, and fully open layouts. Turn state and selection survived. A landscape upward discard gesture worked without moving the table's scroll view.
- Home, nearby lobby, host invitation QR sheet, settings/theme preview, rule guide, history, results, and next-hand opening were checked around the fold. Results were loaded from a completed match produced by the real rules engine into the QA app's save, rather than playing a complete hand manually.
- Largest accessibility text: settings and help scroll; Next Hand remains reachable. Home uses a vertical layout and scaled icon widths. The drawn tile's visual marker has a bounded font size so it stays readable within its slot, while the tile retains its spoken accessibility description.
- Phone regression: portrait uses two rows; both landscape directions use one steady rack. A chow remained beside its owner, and the next drawn tile retained its marker after rotating back to portrait.
- `swift test`: 11 core tests and 5 nearby loopback tests passed, including four encrypted clients and reconnect/recovery behavior.
- Simulator build/run and unsigned generic iOS device builds succeeded. No new physical-device installation or App Store changes were performed.

## Evidence

- [Duo book](duo-book.png)
- [Duo tabletop](duo-tabletop.png)
- [Inner reverse portrait](duo-inner-reverse-portrait.png)
- [Phone portrait](phone-portrait.png)
- [Phone landscape](phone-landscape.png)

## Limits

No physical Duo was available. Actual hinge-angle ergonomics, haptics, speaker balance, camera scanning and nearby radio behavior on a Duo remain untested. The simulator presets do not reproduce every possible hinge angle. No real-device multi-phone nearby match was run in this pass. Payment designs were researched only; purchases and entitlement handling are not implemented or tested.
