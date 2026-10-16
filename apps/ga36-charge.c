/*
 * Charge screen of the GA36. U-Boot passes init=/usr/local/sbin/ga36-charge on a charger plug-in power-on, so this
 * runs as PID 1 on the read-only rootfs. It shows a battery icon for 5 s, then turns the panel off and sleeps in
 * s2idle. A short power-key press shows the icon again, a 2 s hold boots the system (exec /sbin/init), and an
 * unplugged charger powers the board off. Unplugging does not wake s2idle, so an RTC alarm wakes it every 60 s.
 * It must never return: PID 1 exiting panics the kernel. Any error powers the board off.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <linux/input.h>
#include <linux/rtc.h>

#define BATTERY "/sys/class/power_supply/axp20x-battery/capacity"
#define USB_ONLINE "/sys/class/power_supply/axp20x-usb/online"
#define AC_ONLINE "/sys/class/power_supply/axp22x-ac/online"
#define SHOW_MS 5000
#define LONG_MS 2000
#define WAKE_S 60

/* The leading decimal integer of a file, or -1. */
int read_int(const char *path)
{
	FILE *f = fopen(path, "re");
	int v;

	if (!f)
		return -1;
	if (fscanf(f, "%d", &v) != 1)
		v = -1;
	fclose(f);
	return v;
}

/* Width of the battery fill for a capacity in percent; an unreadable capacity (-1) shows empty. */
int fill_width(int capacity, int inner)
{
	if (capacity < 0)
		capacity = 0;
	if (capacity > 100)
		capacity = 100;
	return inner * capacity / 100;
}

static char **init_argv;
static int kmsg = -1;
static int key = -1;
static struct {
	int fd;
	uint32_t crtc, conn, fb, w, h, pitch;
	struct drm_mode_modeinfo mode;
	uint32_t *px;
} drm = { .fd = -1 };

static void say(const char *fmt, ...)
{
	char line[256];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	dprintf(kmsg >= 0 ? kmsg : 2, "ga36-charge: %s\n", line);
}

static void panel_off(void)
{
	struct drm_mode_crtc c = { .crtc_id = drm.crtc };

	if (drm.fd >= 0)
		ioctl(drm.fd, DRM_IOCTL_MODE_SETCRTC, &c);
}

static void off(const char *why)
{
	say("power off: %s", why);
	panel_off();
	sync();
	reboot(RB_POWER_OFF);
	for (;;)
		pause();
}

static long now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int charger_online(void)
{
	return read_int(USB_ONLINE) == 1 || read_int(AC_ONLINE) == 1;
}

/* The first DRM card with a connected connector: its first CRTC (the A33 has one), the preferred mode, and a mapped
 * XRGB8888 dumb buffer. Returns -1 when there is none yet. */
static int drm_open(void)
{
	for (int i = 0; i < 4; i++) {
		char path[32];
		uint32_t crtcs[4], conns[8];
		struct drm_mode_card_res res = { 0 };

		snprintf(path, sizeof(path), "/dev/dri/card%d", i);
		int fd = open(path, O_RDWR | O_CLOEXEC);
		if (fd < 0)
			continue;
		if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) || !res.count_crtcs || res.count_crtcs > 4 ||
		    !res.count_connectors || res.count_connectors > 8)
			goto next;
		res = (struct drm_mode_card_res){ .crtc_id_ptr = (uintptr_t)crtcs, .count_crtcs = res.count_crtcs,
			.connector_id_ptr = (uintptr_t)conns, .count_connectors = res.count_connectors };
		if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
			goto next;
		for (uint32_t j = 0; j < res.count_connectors; j++) {
			struct drm_mode_modeinfo modes[16];
			struct drm_mode_get_connector c = { .connector_id = conns[j] };

			if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) || c.connection != 1 || !c.count_modes)
				continue;
			c = (struct drm_mode_get_connector){ .connector_id = conns[j], .modes_ptr = (uintptr_t)modes,
				.count_modes = c.count_modes < 16 ? c.count_modes : 16 };
			if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c))
				continue;
			drm.mode = modes[0];
			for (uint32_t m = 0; m < c.count_modes && m < 16; m++)
				if (modes[m].type & DRM_MODE_TYPE_PREFERRED)
					drm.mode = modes[m];
			drm.w = drm.mode.hdisplay;
			drm.h = drm.mode.vdisplay;
			struct drm_mode_create_dumb cd = { .width = drm.w, .height = drm.h, .bpp = 32 };
			if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd))
				goto next;
			struct drm_mode_fb_cmd fb = { .width = drm.w, .height = drm.h, .pitch = cd.pitch, .bpp = 32,
				.depth = 24, .handle = cd.handle };
			struct drm_mode_map_dumb md = { .handle = cd.handle };
			if (ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb) || ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md))
				goto next;
			void *p = mmap(NULL, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
			if (p == MAP_FAILED)
				goto next;
			drm.fd = fd;
			drm.crtc = crtcs[0];
			drm.conn = conns[j];
			drm.fb = fb.fb_id;
			drm.pitch = cd.pitch;
			drm.px = p;
			return 0;
		}
next:
		close(fd);
	}
	return -1;
}

/* The power key's event device, with monotonic event times. */
static int key_open(void)
{
	for (int i = 0; i < 16; i++) {
		char path[32], name[64] = "";
		int clk = CLOCK_MONOTONIC;

		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		int fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 && !strcmp(name, "axp20x-pek") &&
		    !ioctl(fd, EVIOCSCLOCKID, &clk))
			return fd;
		close(fd);
	}
	return -1;
}

static void rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t colour)
{
	for (uint32_t r = y; r < y + h && r < drm.h; r++)
		for (uint32_t c = x; c < x + w && c < drm.w; c++)
			drm.px[r * (drm.pitch / 4) + c] = colour;
}

/* Battery outline with a nub on the right, filled to the capacity: green, red under 15 %. */
static void show(void)
{
	int cap = read_int(BATTERY);
	uint32_t bw = drm.w * 2 / 5, bh = bw / 2, t = 8, nub = 16;
	uint32_t x = (drm.w - bw - nub) / 2, y = (drm.h - bh) / 2, inner = bw - 4 * t;
	struct drm_mode_crtc c = { .crtc_id = drm.crtc, .fb_id = drm.fb, .set_connectors_ptr = (uintptr_t)&drm.conn,
		.count_connectors = 1, .mode = drm.mode, .mode_valid = 1 };

	rect(0, 0, drm.w, drm.h, 0);
	rect(x, y, bw, bh, 0xffffff);
	rect(x + t, y + t, bw - 2 * t, bh - 2 * t, 0);
	rect(x + bw, y + bh / 3, nub, bh / 3, 0xffffff);
	rect(x + 2 * t, y + 2 * t, fill_width(cap, inner), bh - 4 * t, cap >= 0 && cap < 15 ? 0xc00000 : 0x00c000);
	if (ioctl(drm.fd, DRM_IOCTL_MODE_SETCRTC, &c))
		off("cannot show the icon");
	say("icon at %d %%", cap);
}

static void boot(void)
{
	int rtc = open("/dev/rtc0", O_RDONLY | O_CLOEXEC);

	say("long press: booting the system");
	/* The alarm survives the close; left armed it would wake the system's first sleep. */
	if (rtc >= 0) {
		ioctl(rtc, RTC_AIE_OFF, 0);
		close(rtc);
	}
	close(drm.fd);
	init_argv[0] = "/sbin/init";
	execv("/sbin/init", init_argv);
	drm.fd = -1;
	off("exec /sbin/init failed");
}

/* Waits up to ms for a power-key press. The icon shows on the key-down, so a press from dark gives feedback at once;
 * then it waits for the release: a hold of LONG_MS from the key-down event boots the system. Returns 1 after a short
 * press, 0 on timeout. */
static int key_press(long ms)
{
	struct input_event ev;
	long down = -1, end = now_ms() + ms;

	for (;;) {
		long left = down < 0 ? end - now_ms() : down + LONG_MS - now_ms();
		struct pollfd p = { .fd = key, .events = POLLIN };

		if (left <= 0) {
			if (down < 0)
				return 0;
			boot();
		}
		if (poll(&p, 1, left) < 0 && errno != EINTR)
			off("cannot read the power key");
		while (read(key, &ev, sizeof(ev)) == sizeof(ev)) {
			if (ev.type != EV_KEY || ev.code != KEY_POWER)
				continue;
			long t = ev.input_event_sec * 1000 + ev.input_event_usec / 1000;
			if (ev.value == 1 && down < 0) {
				down = t;
				show();
			} else if (ev.value == 0 && down >= 0) {
				if (t - down >= LONG_MS)
					boot();
				return 1;
			}
		}
	}
}

/* RTC alarm WAKE_S ahead, so an unplugged charger is noticed in s2idle. Returns -1 if it cannot be set. */
static int alarm_set(void)
{
	struct rtc_wkalrm a = { .enabled = 1 };
	struct tm tm = { 0 };
	int fd = open("/dev/rtc0", O_RDONLY | O_CLOEXEC);
	int r = -1;

	if (fd < 0)
		return -1;
	if (!ioctl(fd, RTC_RD_TIME, &a.time)) {
		memcpy(&tm, &a.time, sizeof(a.time));
		time_t t = timegm(&tm) + WAKE_S;
		gmtime_r(&t, &tm);
		memcpy(&a.time, &tm, sizeof(a.time));
		r = ioctl(fd, RTC_WKALM_SET, &a);
	}
	close(fd);
	return r;
}

static void suspend(void)
{
	int fd;

	if (alarm_set()) {
		/* No alarm: wait awake rather than sleep through an unplug; the caller reads the key. */
		struct pollfd p = { .fd = key, .events = POLLIN };

		say("no RTC alarm, waiting awake");
		poll(&p, 1, WAKE_S * 1000);
		return;
	}
	fd = open("/sys/power/state", O_WRONLY | O_CLOEXEC);
	if (fd < 0 || write(fd, "freeze", 6) != 6)
		say("s2idle failed: %s", strerror(errno));
	if (fd >= 0)
		close(fd);
}

int main(int argc, char **argv)
{
	(void)argc;
	init_argv = argv;
	/* systemd keeps these mounts after the exec, so they get its flags. The kernel mounts /dev already
	 * (CONFIG_DEVTMPFS_MOUNT); the devtmpfs mount is for a kernel without it. */
	mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, NULL);
	kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);

	/* Drivers that deferred their probe may still be coming up; the USB supply waits for the ADC. */
	for (int i = 0; i < 50 && (drm.fd < 0 || key < 0 || read_int(USB_ONLINE) < 0); i++) {
		if (drm.fd < 0)
			drm_open();
		if (key < 0)
			key = key_open();
		if (drm.fd < 0 || key < 0 || read_int(USB_ONLINE) < 0)
			usleep(100000);
	}
	if (drm.fd < 0)
		off("no display");
	if (key < 0)
		off("no power key");

	show();
	for (;;) {
		long end = now_ms() + SHOW_MS;

		while (now_ms() < end) {
			long left = end - now_ms();

			/* One-second slices, so an unplug while the icon shows powers off at once. */
			if (key_press(left < 1000 ? left : 1000))
				end = now_ms() + SHOW_MS;
			if (!charger_online())
				off("charger unplugged");
		}
		panel_off();
		say("panel off");
		for (;;) {
			suspend();
			if (!charger_online())
				off("charger unplugged");
			if (key_press(500))
				break;
		}
	}
}
