# EVIL Rises theme guide

**Approved baseline — WoW Forever, EVIL Rises 0.2.11.** Use the guild window in this version as the visual reference for future pages. NeedRoll inspired the Classic textures and native tabs. The EVIL guild plaque, message of the day, and roster define how those elements fit together here.

## The window, from the outside in

| Element | Approved treatment |
| --- | --- |
| Outer frame | A narrow brass rim surrounds an opaque bronze layer inset by 1 UI unit. The solid warm charcoal interior and tiled `UI-Background-Rock` both start 3 units inside the frame. The tinted `UI-DialogBox-Border` sits inside the outer bounds. Keep the four corners clean throughout a resize. |
| Title bar | Center the current guild message of the day in gold on the dark `_UI-Frame-TitleTileBg` strip. Give both ends 52 units of clearance so long messages stay centered and clear the controls. Show the full clipped message on hover. |
| Window controls | Keep the resize lock immediately left of the Classic close button. The title bar moves the window. The lower-right grip resizes it when unlocked. |
| Navigation | Keep the olive plaque reading **Every Villian Is Lemons** at the far left. It identifies the guild and stays fixed when tabs move. The tab row meets the top of the content inset. |
| Content | Use `CreateInset` for the recessed panel with its opaque base and dark `collections-background-tile` grain. Fine bronze rules separate controls. Translucent row stripes and highlights blend with the panel beneath them. |

## Tabs and selection

Use `CreateGuildTab` and `SetGuildTabFocused`. The native `PanelTopTabButtonTemplate` supplies the silhouette. Exactly one open tab has the raised gold cap and bright label. Inactive tabs sit lower with dark faces and gold lettering. Hover is temporary. The open tab remains draggable.

Anchor each tab’s bottom-left to the previous visible tab’s bottom-right with a **2-unit horizontal gap** and a shared baseline. Start the chain at the guild plaque. When reordering, clear all old anchors before rebuilding the chain. This keeps spacing tied to the rendered widths through a drag, reset, or reload.

## Tables, typography, and color

| Role | Treatment to reuse |
| --- | --- |
| Toolbar | In the roster, the search field sits left and the member count sits right within a 27-unit dark band. Use the same alignment for equivalent filters and counts on new pages. |
| Sortable headings | Use `CreateRosterHeader` and `SetRosterHeaderSelected`. The 22-unit header reads as one dark band. Inactive headings have gold labels and a subdued 1-unit bottom rule. Only the sorted column gets the amber sheen, bright underline, pale label, and direction arrow. |
| Rows | Use the roster’s 23-unit rhythm for comparably dense tables. Alternate `colors.row` and `colors.alternateRow` over the opaque inset. Align each cell to the same column geometry as its heading when the window resizes. |
| Text | Use the client’s `GameFontNormal` family for gold labels, `GameFontHighlight` for readable values and member names, and their small variants for compact headings and cells. Offline names are muted. Keep roster cells on one line. |
| Guild identity and status | Reserve olive and lemon accents for guild identity and selected controls. Online status uses a solid green dot and offline status uses a hollow circle. Keep the status, class icon, rank crown, and member name in that order. Use the existing gold GM and silver officer treatments. |

## Applying the theme to a new page

Build inside the existing page host so the MOTD, plaque, navigation, and resize controls carry across. For example, a Loot table can use the roster header treatment for its sortable item and recipient columns, the existing banding for its rows, and the toolbar count position for its result total. Give each new control an existing visual role before introducing another style.

Use [Theme.lua](EVILRises/Theme.lua) for exact colors, alpha values, textures, and shared constructors. [Panel.lua](EVILRises/Panel.lua) owns the window and tab geometry. [Roster.lua](EVILRises/Roster.lua) shows how to connect table styling to sorting and resizing.

## In-game visual check

- Open the window over a bright scene. Inspect all four edges before, during, and after dragging the resize grip. The world should be visible only outside the frame.
- Switch between a short and a long tab label, reorder them, then reopen the window. Check the single raised tab, even gaps, and fixed guild plaque.
- Sort a text column and an icon column in both directions. Check that the arrow and bright rule follow the sort and that rows stay aligned at the smallest window size.
- Check a long MOTD against the lock and close controls. Its full text should be readable on hover.

When the guild approves a visual change, update the relevant entry and baseline version here. Feature-only releases continue to use this baseline.
