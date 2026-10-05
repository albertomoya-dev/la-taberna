# Changelog

## 0.5.2 — 2026-10-01 — Beta

- Fix the Blizzard achievement UI error `GetCategoryNumAchievements(categoryID, includeSuperceded)` that could occur when an IRS inspection result reached the hidden comparison panel on the Summary page.
- Keep the native comparison panel subscribed to inspection results only while visible. Its event handler and normal comparison behavior are preserved.
- Cover delayed replies, closing/reopening the native panel, lazy loading, and shared-request ownership with regression tests.
- Preserve existing saved history and the accuracy disclaimer.

## 0.5.1 — 2026-10-01 — Beta

- Refresh the CurseForge release package with the current native WoW interface, Activity tab, and sortable character history introduced in prior releases.
- Keep the same gameplay behavior and saved-history format as 0.5.0.
- Retain the MIT license and accuracy disclaimer; exclude personal records, development files, and image metadata from the upload.

## 0.5.0 — 2026-09-30 — Beta

- Add a portrait version of the crest that fits inside the round frame: the emblem and IRS letters, scaled into the visible circle, without the small banner text. The addon-list icon is unchanged.
- Rebuild the window from the game's own templates so it matches Forever's Inspect window: metal frame, crest portrait, title bar and close button, red panel buttons, and the standard inset.
- Switch between **Ledger**, **Activity**, **History** and **Characters** with tabs along the bottom edge. Inspection actions sit at the bottom left; Copy report and Save snapshot at the bottom right.
- Show gold with the game's coin icons and leave out empty denominations, so 90 copper reads as 90c instead of 0g 0s 90c.
- Show counters the game did not report as a grey `--`, like the built-in Statistics view, instead of repeating "Not reported". Hover any figure for its source or the reason it is missing.
- Color character names by class, show the guild as `<Guild>`, and show capture age in minutes, hours, or days.
- Lay out statistics as striped lists under section headings. Shorter labels in the Ledger tab; full names in Activity and tooltips.
- The directory uses the game's search box, Who-list column headers with a sort arrow, and row highlights. It no longer leaves a gap in the button row.
- Draw the window at 120% by default so its text is larger and smoother. `/irs scale 0.6`–`1.6` changes it and `/irs scale reset` restores the default; the window still shrinks to fit small screens. The layout is 690 × 480 before scaling.
- Move **Peak above recorded income** under the gameplay assessment so it shows on the Ledger, Activity and History tabs, with its bar and the share of peak covered by recorded income. Hover it for how to read it.

## 0.4.0 — 2026-09-30 — Beta

- Add an Activity view for all profession ranks and gameplay counters.
- Read five more verified Forever statistics: items disenchanted, resulting materials, fish caught, flight paths taken, and honorable kills.
- Show an explained gameplay assessment with counter coverage, hover evidence, and rules in copied reports. It describes active play or specialization without claiming to detect bots or misconduct. Missing values and gold totals never count against a character.
- Parse correctly grouped integer counters such as 1,234 so large activity totals remain usable.
- Keep the peak-income gap in Activity, preserve old capture times, and protect the expanded saved history from older addon versions.
- No new background scanning, messaging, or external data transfer.

## 0.3.0 — 2026-09-30 — Beta

- Replace the ledger icon with an IRS-inspired fantasy crest featuring a dwarven hammer and an Ironforge gold coin.
- Add **All characters** and `/irs history` / `/irs list`: browse every retained character without a new inspection request.
- Sort by peak gold, total acquired, name, level, last seen, or saved-capture count. Highest peak gold is the default; click a heading to reverse and retain your chosen order across reloads.
- Search by name, realm, guild, or class, with paginated results and access to each saved ledger and its snapshot history.
- Keep missing figures last in either direction and use only the latest saved capture for each row.
- Preserve capture times when browsing. Refreshing a saved character requires that same character to be selected or yourself when applicable.
- Remove the 50-character eviction limit while retaining the latest 20 snapshots per character. Previously evicted records cannot be restored by the update.

## 0.2.0 — 2026-09-30 — Beta

- Add an accuracy disclaimer to the ledger, copied reports, and documentation: figures can be inaccurate, incomplete, or out of date and are not proof of wealth or misconduct.
- Convert WoW's recognized gold/silver/copper icon text into exact copper values, fixing unavailable peak-gap calculations and history changes.
- Upgrade existing saved coin-formatted snapshots without changing their observation times.
- Distinguish counters WoW did not report from actual zeros; hover statistic rows for an explanation.
- Keep an active inspection alive when Refresh is clicked again.
- Prevent missing self-statistics APIs from falling through to another player's values; retain your own wallet even when counters are unavailable.
- Validate saved preferences and history, preserve newer save formats, and enforce history limits on load.
- Fit the ledger and copy-report window to smaller screens and UI scale changes.
- Verify all 31 statistic IDs and labels against client data 1.60.1.70124.
- Add original project artwork, MIT License, installation documentation, and a repeatable release package.

## 0.1.0 — 2026-09-29 — Local preview

- Initial character ledger, self/target statistics, manual copy report, Inspect integration, and bounded local snapshot history.
