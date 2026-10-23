# Public release design

Date: 2026-10-23. Status: draft, waiting for the owner's approval.
Parent design: [`2026-10-14-firmware-design.md`](2026-10-14-firmware-design.md).

## Why

The repository (`Bepok/Debianator`, renamed from `r36s-a33-ga36-debian` on 2026-10-23) is private. The owner wants
other GA36 owners to flash their cards from the GitHub releases, while staying the only maintainer. Today the README
is written for the maintainer: a third of it is about building, and the status line still says the repository is
for maintainers only.

## Who it is for (decided with the owner)

- **Main reader: a GA36 owner who wants to play games, not tinker.** They download a release, flash a card, add
  their games and play, without building anything, opening a terminal or contacting the owner.
- **A smaller group may want to contribute.** Bug reports and device test reports are welcome. Big features only
  after asking the owner first, in an issue. The owner reviews every pull request before it reaches `main`.

## Goals

1. A README that a player can follow from top to bottom: what the image does, how to install it, how to play.
2. In-game save states on hotkeys.
3. A FAQ for the questions a player will ask.
4. Contribution rules and issue templates that match the owner's limits above.
5. The repository switched to public, with the v1.1.0 release published.

## Non-goals and anti-goals

- No history rewrite. The owner's email address stays in the commits and patches (decided 2026-10-23: it is
  already public through their Zephyr contributions).
- No co-maintainers, no collaborators with write access.
- No new places to maintain: no wiki, no Discussions, no website, no chat server.
- **Anti-goal:** anything that points to, ships or hints at where to get games, BIOS files or game data.
- **Anti-goal:** a README a player has to scroll past build instructions to use.

## README (decided with the owner)

Order, top to bottom:

1. **Banner** (`docs/banner.svg`, already in place) and the title.
2. **Status line:** the current release and the tested board, e.g. "v1.1, tested on GA36 board V1.0". The line
   saying the repository is private goes.
3. **What you get:** a short list of the systems and features (RetroArch systems, DOS, Heroes 3, N64 and PSP as
   experimental, both sticks, sleep, the charge screen, saves that survive a reflash), then one "Not yet" line
   (Wi-Fi, arcade, Nintendo DS) and the known limitations. The current system table (folder, file types, core)
   stays here: a player needs the folder names.
4. **Install:** the current Install section, kept as it is apart from wording for the new reader. It already
   covers card size, board revision, checksum, flashing on every OS, first boot, upgrading and going back to
   stock.
5. **Controls (new):** two small tables.
   - **In games:** FN+Start back to the game list; FN+X the RetroArch menu; FN+R1 save state, FN+L1 load state,
     FN+Left and FN+Right change the slot (new, see below); FN+Vol brightness; volume keys; power key short press
     sleep and wake, held over 2 s power off; L1+R1+Select switches the PlayStation pad to analog.
   - **In the game list (EmulationStation):** move, launch, back, main menu, game options, favourites, page jumps.
     **Every entry is checked on the device before it is written** (see "Checks"): this ES build (fcamod) may not
     match the stock EmulationStation layout.
6. **FAQ (new),** see below.
7. **Per-system notes:** the current DOS, Heroes 3, N64 and PSP paragraphs, unchanged in substance.
8. **Footer:** a link to the developer page, the Sources section (kept in the README because the GPL source offer
   must be easy to find), then Licence (GPL-2.0, the "no games, BIOS files or game data" note, the banner credit).

## Save-state hotkeys (decided with the owner)

- FN+R1 save state, FN+L1 load state, FN+Left / FN+Right previous / next slot. FN is already the RetroArch hotkey
  (`input_enable_hotkey_btn = "12"`) and none of these clash with FN+Start or FN+X.
- A change to `rootfs/overlay/etc/skel/.config/retroarch/retroarch.cfg` only (button ids from
  `rootfs/overlay/etc/emulationstation/es_input.cfg`: L1 4, R1 5, Left 15, Right 16), with the matching lines
  added to the retroarch.cfg check in `tests/rootfs.sh`.
- States go where they go now (`savestate_directory = "/roms/saves"`), so they survive a reflash like saves do.
- **It ships in v1.1.0 (owner, 2026-10-23).** The v1.1.0 tag (now on `5621aca`, draft release unpublished) moves to
  the commit with the hotkeys and the image is rebuilt by CI; the owner gave the word for moving the tag. The
  first public release then has everything the README describes.

## FAQ (decided with the owner)

The owner asked for "how to flash" and "where saves go"; the rest were proposed and accepted.

1. **How do I flash the card?** Short pointer to Install: balenaEtcher or Raspberry Pi Imager on Windows and
   macOS, `dd` on Linux; card size.
2. **Where are my saves, and does an update wipe them?** `saves` on the `ROMS` partition (save files and save
   states), Heroes 3 in `heroes3/Saves`. An update written with `dd` keeps `ROMS`; Raspberry Pi Imager erases the
   whole card (as Install says), so copy `saves` off first.
3. **Will it work on my R36S?** Only on the GA36-MB clone (Allwinner A33). The original R36S and most clones use
   the Rockchip RK3326 and need ArkOS or similar. How to tell: the board marking `GA36-MB`, or the stock system
   being a vendor EmuELEC on Linux 3.4 (the facts are in `docs/hardware/`). Board revisions V1.1 and V1.2 are
   untested: a test report is welcome.
4. **Where do ROMs and BIOS files go?** `ROMS/<system>` and `ROMS/bios`, with the BIOS file names the image's
   cores need (e.g. PlayStation). Names only, never a source.
5. **How do I quit a game, save, or open the menu?** Points to Controls.
6. **Why is N64, PSP or DOS slow?** The chip is at the bottom of what they need; points to the per-system notes.
7. **How do I add DOS games or Heroes 3?** Points to the per-system notes.
8. **Can I use Wi-Fi, a keyboard or a mouse?** Wi-Fi: not yet, planned for v1.2 with a USB dongle. Keyboard and
   mouse: through a USB OTG adapter, configured but untested.
9. **How do I charge it, and what is the screen while it is off?** The charge screen (battery icon, then dark),
   short press shows it again, hold over 2 s to boot.
10. **Something does not work: where do I report it?** An issue with the bug-report template.

## Developer page

- Moves out of the README into `docs/development.md`: "Build and flash it yourself", "Hardware", "Development"
  (with the USB console shell), and a link to the porting plan and the specs.
- `CONTRIBUTING.md` at the root, short: bug reports and device test reports welcome; open an issue and wait for the
  owner's answer before starting a feature; small fixes can go straight to a pull request; the owner reviews and
  merges every pull request; **every commit carries a DCO `Signed-off-by` line (`git commit -s`; owner,
  2026-10-23)**, so contributed patches can go upstream later, and a pull request without it is not merged; no ROMs, BIOS files or game data in issues or pull requests; points to
  `docs/development.md` for building and to the hardware notes for how device checks are recorded.

## Issue templates

`.github/ISSUE_TEMPLATE/` with two GitHub issue forms:

- **Bug report:** board revision (marking), image version (release name), what happened, what was expected, steps,
  and optionally the USB console log.
- **Device test report:** board revision, image version, what was tried (boot, picture, buttons, sticks, sound,
  sleep, charging, which systems), what worked and what did not.

Blank issues stay allowed, for questions and for asking before a feature.

## Who can change `main` (builder's call, stated for the owner)

The owner's requirement is that nothing reaches `main` without their review. In a public personal repository with
no collaborators, **only the owner can push or merge**: outsiders can only open pull requests from forks, and
only the owner can merge them. So no branch protection rule, ruleset or `CODEOWNERS` file is needed, and the owner
keeps pushing directly as today. If a collaborator is ever added, branch protection comes then.

The same holds for release tags: only the owner can push them, so only the owner can start a release build.

CI (`.github/workflows/image.yml`) runs only on tag pushes and manual dispatch, never on pull requests, so a pull
request from a fork cannot run code with the workflow's write token.

## Repository settings at the switch

- Visibility: public.
- Issues on (already), wiki off (already), Discussions off (already), Projects off (now on, unused).
- Description and topics set (e.g. `r36s`, `allwinner-a33`, `debian`, `retro-handheld`, `emulationstation`).
- Social preview: a PNG made from the banner (GitHub does not take SVG there).
- **Not set:** "Block command line pushes that expose my email" stays off: it would block the owner's Zephyr pushes,
  which must use their real address.

## Clean-up before the switch

- README Licence: the "No games, BIOS files or game data" paragraph (written and accepted on 2026-10-23, including
  the sentence that such issues and pull requests are closed).
- Done on 2026-10-23 (owner): the implementation plans and plan reviews (`docs/plans`, `docs/review`), where all
  the local paths were, moved to the private repository `Bepok/Debianator-notes`; old commits keep them (no history
  rewrite). The kernel device-tree patches were folded into one board patch the same day. Before the switch the
  builder repeats a grep of the current files for `~/` and `/home/` (other than the device's `/home/ga36` and the
  vendor's `/home/lxl`) and replaces any hit with a neutral placeholder. Builder's call: the titles of games used in
  device checks stay in the hardware notes; a title says what was tested, not where to get it.
- Stays as is, decided with the owner: the vendor developer's name, email and build path in the hardware notes
  (provenance of the vendor's GPL kernel), `docs/hardware/sys_config.fex`.
- The release draft's two "FILL IN" lines (tested board, checked by) are filled in by the owner when publishing.

## Who does what at the switch (builder's call)

- The builder publishes the release and switches the repository to public with `gh`, **each only after the owner's
  explicit go-ahead in that session**: both are outward-facing and hard to undo.
- The social preview image is a web-only upload: the builder makes the PNG, the owner uploads it.

## Order

1. Merge the README, Controls, FAQ, developer page, `CONTRIBUTING.md`, issue templates, save-state hotkeys and
   clean-up into `main`.
2. Move the v1.1.0 tag to that commit (delete the draft release and the remote tag, tag again, push); CI builds
   the image and makes a new draft release.
3. Flash the CI image and check the save-state hotkeys and every Controls entry on the device; fix and repeat 2 if
   anything is wrong.
4. Publish the v1.1.0 release (owner's go-ahead).
5. Switch the repository to public and apply the settings above (owner's go-ahead).

## Checks

- `tests/rootfs.sh` passes with the new hotkey lines; the full test set passes.
- On the device (V1.0), with the CI-built v1.1.0 image, recorded in `docs/hardware/hardwareAnalysis.md`: save state, load state and slot change in
  one RetroArch game, and the state file appears in `ROMS/saves`; every ES button in the Controls table does what
  the table says.
- Every link in the README, `CONTRIBUTING.md` and `docs/development.md` resolves (relative links checked locally).
- After the switch: the repository page, the banner and the release download work from a browser that is not
  logged in.

## Left to the builder

- Wording of the README, FAQ, `CONTRIBUTING.md` and templates, within the order and content above.
- How the per-system notes and system table are trimmed or grouped, as long as nothing a player needs is lost.
- Exact topics and repository description.
