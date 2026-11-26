# EVIL Rises

EVIL Rises adds a guild Bounty Board to the standard Guild & Communities window in WoW Forever. Select the skull icon below the built-in tabs on the right, or type `/evil`.

Choose **Post a bounty** and enter a character name, use your current target, or right-click a player portrait and choose **Create bounty**. Choose a faction, select **Kill on sight**, **Camp**, or both, and set the gold, silver, and copper reward. Add a reason if you want guildmates to know the story.

Whisper the poster to agree on completion and payment. Posters withdraw their own listings once settled. Open listings expire seven days after posting. Guildmates running this generation of EVIL Rises exchange updates automatically.

## Crafting Orders

Select the crate beneath the Bounty Board. Search **Recipes** by name or profession, filter by guild coverage, or select a member under **Crafters** to browse what they know. Open a recipe for its materials and source. For recipes that produce an item, choose a quantity, who supplies materials, an optional tip, and either a specific crafter or the whole guild.

Under **Orders**, switch between your requests, orders assigned to you, and open requests you can craft. Accept or decline a request, record materials, and mark delivery complete. Guildmates running version 0.5.4 share profession and order updates automatically.

## Member profiles

Left-click a guildmate in the member list to open their native details card and attached gear flyout. Hover over an equipped slot for its item tooltip or drag the model to rotate it. A visible character uses their live appearance. Away or offline members can show a model dressed from their last shared equipment. Profession ranks appear when available. Version 0.5.7 shares each character�s carried gold, silver, and copper with guildmates running EVIL Rises. The flyout shows their last shared balance while offline. Use **Hide gear & professions** beneath the card to collapse the flyout.

## Install

Extract the release ZIP into `World of Warcraft/_forever_/Interface/AddOns/` and reload the interface. When upgrading manually, replace the old `EVILRises` addon folder. Existing saved variables can stay in place. Use `/evil version` to check the installed version.
## Raid night and guild business

- **Chat** opens guild chat. Members who can read officer chat get a second channel there. A filled gold roster crown marks the guild master, and a gold outline marks ranks with officer permissions.
- **Guild** keeps the calendar, polls, and bulletin together. Under **Raids** you'll find sessions and attendance. Under **Loot** you'll find wishlists, standings, and loot history.
- **Alliances** holds guild pacts, allied bulletins, and chat.
- **Recruitment** and **Leadership** give officers tools for trials, ranks, officer notes, and the audit log. Available actions depend on guild permissions.

Guildmates running EVIL Rises sync automatically at login, every 60 seconds, and when they open the guild window. If you missed a bounty or its withdrawal while offline, your board can catch up when the author is back online.

## Commands and options

- `/evil` or `/evilrises` opens or closes the guild window. Your guild keybind and guild menu button work too.
- `/evil version` shows the installed addon version.
- Drag the tabs to put your favorites first. Drag the bottom-right corner to resize the window, then click the padlock beside the close button to lock the size.
- In **Settings**, adjust alerts and enabled features. For a bug report, choose **Open debug window**, reproduce the problem, then choose **Copy log**.

## Download and install

[Download the EVIL Rises ZIP from GitHub Releases](https://github.com/alienvisa/EVIL-Rises/releases/latest). With the game closed, unzip the download and copy the `EVILRises` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Check that `AddOns/EVILRises/EVILRises.toc` is in place, then enable **EVIL Rises** in the character screen's AddOns list.

Found a bug or have an idea for the guild? [Open an issue on GitHub](https://github.com/alienvisa/EVIL-Rises/issues).

*Stay ticklin and stay evil.*

## Contributing and releases

Use a Conventional Commit PR title, such as `feat(roster): add filters` or
`fix: repair guild sync`, to choose the release bump. Prefer squash merging with
the PR title as the commit subject. GitHub's default merge commit also carries
the PR title on the first line of its body. PR CI previews the bump from the
title and checks Lua 5.1 syntax, guild sync, bounty expiry, chat permissions, versioning, release recovery, and
the install ZIP.

In GitHub, enable squash merging, set the default squash commit message to
**Pull request title and description**, and disable merge commits and rebase
merging. Protect `main` by requiring a pull request and the **Tests** status check
from PR CI. Put any `BREAKING CHANGE:` footer in the PR description so it carries
through to the squash commit.

After CI passes on `main`, the workflow builds and validates a versioned ZIP with
BigWigs and stages it on a draft GitHub release. It uploads that exact ZIP to
CurseForge and publishes the GitHub draft after validating the upload receipt
and ZIP checksum. Set the `CF_PROJECT_ID` repository variable and the
`CF_API_TOKEN` secret before enabling publishing.

Pushes to `main` trigger publishing after CI passes. The latest stable Git tag
sets the version baseline. A Conventional Commit with `!` or a `BREAKING CHANGE:`
footer selects a major bump. A `feat` title selects a minor bump. Other messages,
including ordinary commit titles, default to patch. The largest bump applies if
several commits accumulated since the last release.

After publishing, GitHub Actions opens or updates a PR to sync the version in
`EVILRises/EVILRises.toc`. Enable **Allow GitHub Actions to create and approve pull
requests** in **Settings → Actions → General**. Approve the bot PR's CI run if
GitHub requires it, then merge the PR with its original title. A merge that only
syncs the TOC version does not publish another release.

### Recovering a release

Rerun the original release job. It reuses the staged ZIP and any valid
`curseforge-upload.json` receipt. A push to `main` also resumes the pending
release from its original tag before allocating another version. If staging
never finished, the job rebuilds from that tagged commit.

If the job reports an unconfirmed CurseForge upload, inspect the project's
upload history, including pending files, and the run's **release-files** artifact:

- If the artifact contains `curseforge-upload.json`, attach it to the draft and
  rerun the job.
- If CurseForge accepted the exact staged ZIP and the receipt was lost, verify
  the file against the staged ZIP, add its numeric CurseForge file ID as `id`
  to a copy of the draft's `curseforge-attempt.json`, and attach that copy as
  `curseforge-upload.json`. Rerun the job.
- If you confirm CurseForge accepted no file, remove `curseforge-attempt.json`
  from the draft and rerun the job.
