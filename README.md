# EVIL Rises — WoW Forever
<p align="center">
  <img width="211" height="192" alt="EVIL" src="https://github.com/user-attachments/assets/a94d0bac-87fc-4c19-8010-82e03c43826f" />
</p>

EVIL Rises is the guild addon for **EVIL: Every Villian Is Lemons**. Open your usual guild window or type `/evil` to see the guild message of the day and who's online. From the same window you can find a crafter, check the raid calendar, or put a bounty on an enemy player.

Check us out on CurseForge: [Evil Rises](https://www.curseforge.com/wow/addons/evil-rises)

## Got ganked? Put a price on their head

Right-click the enemy player and choose **Create bounty**. The board opens with their name, class, and faction filled in. Lost sight of them on the corpse run? Open **Bounty** and type their name yourself.

Choose **Kill on sight**, **Camp**, or both. Set the reward in gold, silver, and copper, add a reason if you like, and post it. Your guildmates can see who they're after and why. You can withdraw your own bounty when the score is settled.

## Who's online, and who can make that?

On the **Roster**, a solid green dot means online and a hollow circle means offline. Click a column heading to sort, then click it again to reverse the order. Click a name to see the member's notes, professions, and linked characters.

Looking for an enchanter before raid time? Sort the roster by **Primary professions** to find one. If you need a particular recipe, open **Professions** to look it up, see which guildmates know it, and place a craft order.

Open a guildmate's roster entry to see their last shared equipment, even while they're offline. EVIL Rises shares gear changes automatically. Item names use their rarity colors, and hovering over a piece shows its WoW item tooltip.

## Raid night and guild business

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
`fix: repair guild sync`. Prefer squash merging with the PR title as the commit
subject. If you use GitHub's **Create a merge commit** option, keep the default
merge subject and the PR title on the first line of the commit body. CI checks the
title, Lua 5.1 syntax, guild sync, versioning, release recovery, and the install ZIP.

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

Pushes to `main` trigger publishing after CI passes. `feat` bumps minor, a title with `!`
or a `BREAKING CHANGE:` footer bumps major, and other allowed types bump patch.
The largest bump applies if several commits accumulated since the last release.

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
