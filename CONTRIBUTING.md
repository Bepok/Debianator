# Contributing

Debianator has one maintainer, who reviews and merges every pull request.

## Welcome without asking

- **Bug reports:** open an issue with the "Bug report" form. Give the board revision (the marking on the board) and
  the image version (the release name); a USB console log helps.
- **Device test reports:** especially from V1.1 and V1.2 boards, which are untested. Use the "Device test report"
  form; [docs/development.md](docs/development.md), "Hardware", says how to keep a boot log.
- **Small fixes** (a wrong sentence, a broken link, a one-line bug fix): open a pull request directly.

## Ask first

Open an issue and wait for the maintainer's answer before you start a feature or any larger change. A pull request
for a feature nobody agreed to may be closed.

## Pull requests

- **Every commit carries a DCO sign-off:** commit with `git commit -s`, which adds
  `Signed-off-by: Your Name <you@example.com>`. It certifies the
  [Developer Certificate of Origin](https://developercertificate.org/). The kernel and U-Boot patches are meant to go
  upstream, which needs it. A pull request with an unsigned commit is not merged.
- Run the checks before you open it: `./build.sh run tests/<name>.sh` for what you touched, or all of `tests/`. CI
  does not build pull requests.
- Changes that affect the device (boot, picture, buttons, sound, sleep, charging) are checked on a real console;
  results are recorded in [docs/hardware/hardwareAnalysis.md](docs/hardware/hardwareAnalysis.md). Say in the pull
  request what you checked and on which board.
- Building and the development loop: [docs/development.md](docs/development.md).

## Never

No ROMs, BIOS files or game data, and no links to them, in issues, pull requests or commits. Such issues and pull
requests are closed.
