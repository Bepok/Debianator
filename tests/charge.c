/* Host unit test of the pure helpers in apps/ga36-charge.c. Built and run by tests/charge.sh. */
#define main ga36_charge_main
#include "../apps/ga36-charge.c"
#undef main

static int fail;

static void want(int got, int expected, const char *what)
{
	if (got != expected) {
		printf("FAIL: %s: got %d, want %d\n", what, got, expected);
		fail = 1;
	}
}

static void put(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	fputs(text, f);
	fclose(f);
}

int main(int argc, char **argv)
{
	char path[4096];

	want(fill_width(50, 200), 100, "fill_width(50, 200)");
	want(fill_width(100, 200), 200, "fill_width(100, 200)");
	want(fill_width(0, 200), 0, "fill_width(0, 200)");
	want(fill_width(-1, 200), 0, "fill_width(-1, 200)");
	want(fill_width(150, 200), 200, "fill_width(150, 200)");

	/* argv[1] is a scratch directory. */
	snprintf(path, sizeof(path), "%s/capacity", argv[1]);
	put(path, "87\n");
	want(read_int(path), 87, "read_int of \"87\\n\"");
	put(path, "x\n");
	want(read_int(path), -1, "read_int of \"x\\n\"");
	snprintf(path, sizeof(path), "%s/missing", argv[1]);
	want(read_int(path), -1, "read_int of a missing file");

	if (!fail)
		puts("PASS");
	return fail;
}
