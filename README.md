# 福州麻将 for iPhone

The native app plays full rounds of Fuzhou Mahjong in Simplified Chinese. The same rules engine powers offline solo play and nearby tables.

- **单机对战** starts a game with three computer players. On subsequent launches, **继续单机** resumes it. Use **••• → 新开一局** to start the shuffle and deal on a separate table and **••• → 返回第二张牌桌** to resume that table. Both save locally after each move.
- **附近联机** uses Apple peer-to-peer Wi-Fi. On the host's phone, tap **创建牌桌**. On each guest's phone, tap the table by name, enter its invite code, or use **扫描邀请码** to scan the host's **分享邀请** QR code. Allow Local Network access when prompted. The host can start with at least one guest, and computer players fill empty seats.
- The live table highlights draws, keeps melds beside their owners, and names **本局金牌** above the table. The hand stays pinned below the board. Flick a playable tile upward to discard it, or select it and tap **出牌**. Tap **理牌** to drag tiles into order, **自动排序** to restore the default order, and **完成** to return to play. The **牌河** button shows the discard history and melds. The game deals 16 tiles, handles 补花, 金牌, 抢金, 吃、碰、明杠、暗杠、加杠, discard wins and self-draw. Results itemize the Fuzhou points and carry scores and dealer continuation into the next hand.
- Table sounds are bundled for offline use. By default, nearby play sounds each player's own moves on their phone. **设置 → 同桌只播自己的操作** changes this, and **牌桌音效** mutes the table.
- A guest who temporarily disconnects keeps their seat. The host can resume after the guest returns or let an AI take over a disconnected seat. An active nearby match lives in the host's process, so force quitting the host ends it.

## Build and run

Open [FuzhouMahjong.xcodeproj](FuzhouMahjong.xcodeproj) in Xcode and choose the **FuzhouMahjong** scheme. The deployment target is iOS 17. The app has no third-party dependencies. If target configuration changes, run `xcodegen generate` here. Run `swift test` to check the native rules and four encrypted clients on a loopback connection.

For a cruise test, install the app on each iPhone before departure. Enable Airplane Mode, turn Wi-Fi back on, and keep cellular off. Test discovery, a complete hand, and a reconnect with the phones off every Wi-Fi access point. The loopback test exercises the game and network protocol. It cannot reproduce iPhone discovery or the radio behavior on a ship.

[Fuzhou rules reference](https://github.com/EpicOrange/riichi_advanced/blob/main/documentation/fuzhou.md) · [Apple peer-to-peer networking](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api#Peer-to-peer-networking)
