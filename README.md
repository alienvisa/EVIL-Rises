# EVIL Rises

A World of Warcraft: Forever addon for **EVIL: Every Villian Is Lemons**.

## Install and try it

1. Copy the `EVILRises` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Start Forever and enable **EVIL Rises** in the AddOns list.
3. Open the guild window with your guild keybind, the guild micro-menu button, `/evil`, or `/evilrises`. Use `/evil blizzard` for the original window or turn off the replacement in **Settings**.
4. Drag the tabs to reorder them. The guild name stays at the left. **Settings** can restore the default order.
5. Click a roster header to sort and click it again to reverse the order. The icon headers sort by status, class, and guild rank. A gold crown marks the guild master and a silver crown marks the second rank or a rank named Officer.
6. Click a member's name for notes, profession details, and linked characters. Enter another roster name or `Name-Realm` to link that character as an alt. The order, login setting, and alt links are saved on the account. Alt links are scoped to the guild.

Race and professions appear when the client supplies member data. Officer notes follow Blizzard's guild permissions. The member details can show your own gear or inspect a nearby, eligible guildmate. Raid attendance and loot history have display slots for future tracking. **Roster** and **Settings** are active in this build.

If a Forever update flags the addon as out of date, compare the TOC's Interface number with the fourth value printed by `/dump select(4, GetBuildInfo())`. The initial target is Forever 1.60.1 (Interface 16001).

## Build and distribute

From the repository root in PowerShell:

```powershell
./scripts/Build-Package.ps1
```

The script creates `dist/EVILRises-<version>-forever.zip` from the version in `EVILRises/EVILRises.toc`. The archive contains the installable `EVILRises` folder at its root.

- **CurseForge** — Upload the ZIP to the EVIL Rises project and select the matching Forever game version.
- **WowUp** — Players using WowUp with CurseForge can use the CurseForge listing, subject to the project's third-party distribution settings. For direct GitHub installation through WowUp, attach the ZIP to a release on a public distribution repository. Keep the `-forever.zip` suffix.

[CurseForge upload guide](https://support.curseforge.com/support/solutions/articles/9000197242-file-types-and-additional-fields) and [WowUp source and ZIP guide](https://wowup.io/guide/get-addons/overview)
