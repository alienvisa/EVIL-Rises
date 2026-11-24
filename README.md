# EVIL Rises

A World of Warcraft: Forever addon for **EVIL: Every Villian Is Lemons**.

## Install and try it

1. Copy the `EVILRises` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Start Forever and enable **EVIL Rises** in the AddOns list.
3. In game, enter `/evil` or `/evilrises` to open the guild panel. Use `/evil version` to see the installed version or `/evil help` to list the commands.
4. Check **Show a message on login**, then use `/reload` to verify that the setting persists. The setting applies across characters on the account.

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
