# U-Boot patches: upstream comments

Whether the patches in `uboot/patches/` could go upstream, and what stands in the way. Checked 2026-10-17.

U-Boot moved to `https://git.u-boot-project.org/u-boot/u-boot.git`; development is on `main`. Patches go to the
mailing list (`doc/develop/sending_patches.rst`, DCO sign-off). The docs have no AI policy.

- `0001-sunxi-probe-the-MUSB-gadget-in-board_usb_init`: the bug is still in `main` (2026-10-16): with
  `USB_ETHER` off, `ums`, fastboot and the ACM console fail with "Controller uninitialized", because only
  `usb_ether_init()` probes the sunxi MUSB device. Known and unfixed upstream (patchwork, project `uboot`):
  - Sam Edwards, 2023-06, "usb: musb-new: sunxi: make compatible with UDC/DM gadget model" (v2 2/2,
    patchwork 1792570): deferred.
  - Aren Moynihan, 2023-12, "usb: musb-new: sunxi: support usage with DM_USB_GADGET": superseded by Sam's.
  - Michael Walle, 2024-07, "sunxi: board: probe USB gadget" (probe in `board_init()`, patchwork 1959517):
    deferred, no replies.

  In the 2024 thread on Sam's patch the sunxi custodian, Andre Przywara, said `board_usb_init()` is a legacy hook
  sunxi should not need, that the DM support "is the right way to go", that `DM_USB_GADGET` should be forced for all
  sunxi boards in Kconfig with no `#ifdef`s, and that the Ethernet gadget holding the UDC (blocking `ums` until it is
  unbound) needs solving first. Our patch is the `board_usb_init()` approach, so it is unlikely to be taken as is.
  The fix worth sending is a respin of Sam's conversion on `main`, with `DM_USB_GADGET` selected for sunxi, tested on
  the GA36 (ACM console, `ums`, Ethernet gadget conflict), crediting Sam. If it lands, drop our 0001.
- `0002-sunxi-ga36-pick-init-from-the-AXP-boot-source`: board-specific glue with a hard-coded path. Local only.
