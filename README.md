# 同桌麻将·福州 for iPhone

The native app plays full rounds of Fuzhou Mahjong in Simplified Chinese. The same rules engine powers offline solo play and nearby tables.

- **单机对战** starts a game with three computer players. On subsequent launches, **继续单机** resumes it. Use **••• → 新开一局** to start the shuffle and deal on a separate table and **••• → 返回第二张牌桌** to resume that table. Both save locally after each move.
- **附近联机** uses Apple peer-to-peer Wi-Fi. On the host’s phone, tap **创建牌桌**, choose the table rules, then tap **确认创建**. On each guest's phone, tap the table by name, enter its invite code, or use **扫码加入** to scan the host's **分享邀请** QR code. Allow Local Network access when prompted. The host can start with at least one guest, and computer players fill empty seats.
- The live table shuffles and deals in place. Tap **跳过动画** to settle your table immediately. Reduce Motion uses a short status and settles the tiles in place. The table highlights draws, keeps exposed melds beside the remaining tile backs, lets you tap a seat to inspect its sets at hand-tile size, and names **本局金牌** above the table. The hand stays pinned below the board. Flick a playable tile upward to discard it, or select it and tap **出牌**. Both paths ask for confirmation before discarding gold and show **本局只能自摸** after it is discarded. Tap **理牌** to arrange your tiles, **自动排序** to restore the default, and **完成** to return to play. Each solo save remembers its rack order for the current hand. **牌河** shows the discard history and melds.
- A win reveals the winning hand and its melds on the felt. Tap **查看结算** for the score breakdown after a win or draw, and **返回牌桌** to inspect the completed table again. **下一局** is on the scorecard. Nearby players can inspect scores independently. When the host starts another hand, guests return directly to the new table.
- Table sounds are bundled for offline use. By default, nearby play sounds each player's own moves on their phone. **设置 → 同桌只播自己的操作** changes this, and **牌桌音效** mutes the table.
- Open **设置 → 外观** to follow the system appearance or choose Light or Dark. Automatic pairs Snow White with Glazed Porcelain in Light mode and Jade/Walnut with Classic in Dark mode. The five boards and six tile sets can be mixed independently for 30 combinations in solo and nearby play. Older selections for retired styles return to Automatic. Tile material shapes the sound and feel of a tap, and the playing surface softens the sound and vibration on contact.
- **••• → 玩法** opens replayable rule examples. On a table, **?** opens the relevant lesson, and tapping **本局金牌** explains gold. The guide includes static examples for Reduce Motion and descriptions for VoiceOver.
- Nearby discovery resumes after returning to the app. An invitation search offers retry and cancellation after 15 seconds. Hosted computer turns keep running while the host visits other app screens.
- Once a hand starts, a guest who temporarily disconnects keeps their seat. Seats in the waiting room are available to other guests until the first deal. After reopening the app, **返回上次牌桌** searches for the original host and restores the reserved seat and hand. Returning to the lobby preserves the seat. Leaving explicitly releases it when the host confirms. If automatic reconnection cannot reach the host, the guest can retry or tap **返回大厅**. The host can resume after the guest returns or let an AI take over a disconnected seat. An active nearby match lives in the host's process, so force quitting the host ends it.

## Free play and lifetime unlock

Joining a nearby table is always free. The free version also allows two new solo hands each local day, shared between both saved tables. A hand means one deal through a win or draw; resuming a saved hand does not use another allowance. Tile styles and the rules guide remain free.

**14天免费体验** explicitly activates 14 days of unlimited solo play and hosting through a zero-price, non-consumable App Store product. Activate it online before travelling. It never bills automatically, and restoring it does not restart the clock. **永久解锁完整版** is a one-time **US$4.99** purchase for unlimited solo play and hosting; the app displays Apple's localized price. Guests do not need to purchase. A trial expiring or a purchase being revoked does not interrupt an active hand; access is checked before the next deal or a new hosted match.

Verified purchases are cached in the device Keychain and reconciled with StoreKit at launch and foreground. Once activated, the trial or lifetime entitlement works offline. Restoring onto another device requires an internet connection and the purchasing Apple account. Local daily counters include a clock high-water mark; moving the clock backwards does not replenish the allowance.

See [StoreKit setup and validation](StoreKitProducts.md) for product identifiers, release prerequisites, and isolated local purchase tests. Local StoreKit test purchases do not charge an Apple account.

## iPhone Duo

On iOS 27.1 and later, the table uses the system hinge regions. Partially folded book mode puts the table beside the hand; tabletop mode puts the table above the hand and actions. Fully open and closed modes use the available display. Wide displays keep one continuous rack, while narrow portrait displays use two rows. Folding preserves the match, selected tile, and manual rack order. Home, lobbies, invitations, help, history, opening animations, results, and settings keep their interactive content outside an active hinge region.

Build with an SDK containing `ArrangementView` and reserved-region APIs to enable folded layouts. Older SDKs and iOS versions retain the standard phone layout. Simulator checks do not replace testing physical hinge angles, reachability, haptics, or nearby radios on a real Duo.

## Build and run

The working checkout is `~/work/FuzhouMahjong`.

Open [FuzhouMahjong.xcodeproj](FuzhouMahjong.xcodeproj) in Xcode and choose the **FuzhouMahjong** scheme. The deployment target is iOS 17. The app has no third-party dependencies. If target configuration changes, run `xcodegen generate` here. Run `swift test` to check the native rules and four encrypted clients on a loopback connection.

For a cruise test, install the app on each iPhone before departure. Enable Airplane Mode, turn Wi-Fi back on, and keep cellular off. Test discovery, a complete hand, and a reconnect with the phones off every Wi-Fi access point. The loopback test exercises the game and network protocol. It cannot reproduce iPhone discovery or the radio behavior on a ship.

[Fuzhou rules reference](https://github.com/EpicOrange/riichi_advanced/blob/main/documentation/fuzhou.md) · [Apple peer-to-peer networking](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api#Peer-to-peer-networking)
