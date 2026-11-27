# Game table animation and winning hand reveal

Keep the player at the same table through opening play and a win. The board, seats, rack, and action row should occupy the same space throughout the hand. This plan covers solo and nearby play.

## 1. Shuffle and deal on the board

- Open directly on the live table. Shuffle the tile backs at the center, stack them into the wall, then deal toward the four seats. Reveal the local rack as its tiles arrive. Other players’ tiles stay face down.
- Reserve the usual space for the rack and action row. Show **跳过动画** in the action row during the deal. Skipping settles the table immediately and enables play as soon as the opening state allows it.
- Use the live table’s wall and reserve positions for ordinary draws, flower replacements, and kong draws. The visible draw lands at the receiving seat or in the local drawn-tile slot.
- With Reduce Motion, show a short shuffle/deal status and settle the tiles in place. Resuming a saved hand or reconnecting mid-hand should open on the current table state.
- In nearby play, the host controls the opening and the match state. Each player can skip their own animation. When the host advances the match, guests settle onto the current board at once.

## 2. Reveal the winning hand before scores

- When a win is confirmed, hold the final board and show the winner’s name and win type, **胡**, **自摸**, or **抢金**. Highlight the winning seat and tile.
- Reveal the full winning hand and the winner’s point gain in a compact area on the felt, with exposed sets kept in their original groups. Keep other players’ concealed tiles private during play. Use a wrapping layout on narrow screens and keep the reveal clear of the Duo hinge.
- Leave the winning hand visible until the player taps **查看结算**. The scorecard shows the current scoring details, with **返回牌桌** available to inspect the winning hand again. On **流局**, offer the scorecard from the completed board.
- Offer **查看四家手牌** from the solo scorecard after a win or draw. Nearby hosts can enable the same option before play. Guests confirm the rule before joining, and the review keeps each player's name from settlement.
- Keep **下一局** on the scorecard. In nearby play, each person can open the scorecard independently. When the host starts the next hand, the table and scorecard follow the new hand together.

## Implementation order

1. Move the opening animation into the live board and verify that playing, skipping, rotating, and reconnecting all arrive at the same playable hand.
2. Add the settled-board reveal for each win type, then make the existing scorecard open on demand. Reuse the completed hand and score information already used by the scorecard.
3. Test both changes together across a complete hand and the start of the next hand.

## Acceptance checks

- On a standard iPhone in portrait and landscape, check that the board, seats, rack, and controls stay anchored through the shuffle, deal, draws, win, and next deal. Check both an AI win and a player win.
- On iPhone Duo, verify book and tabletop layouts and rotate or fold during the opening and winning reveal. Verify that tiles fit, the hinge area stays clear, and the primary action remains reachable.
- Check **胡**, **自摸**, **抢金**, and **流局**. For wins, verify the winning tile appears once, exposed sets are readable, and the scorecard agrees with the revealed hand. Check that the reveal stays until the player acts.
- Check Reduce Motion, VoiceOver, audio cues, and skipping. With two nearby phones, skip on one device, inspect scores independently, and verify reconnect and host-controlled advancement.
