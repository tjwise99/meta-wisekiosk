/* Boot CPU and disk-I/O sampler for the Pi Zero W kiosk.
 *
 * Replaces the shell version, which cost 2.3s of CPU across one boot -- ~5% of
 * the boot's total CPU work, on a core that is 0% idle through startup. An
 * instrument that large changes the thing it measures: rewriting the shell
 * sampler from /proc/diskstats to /sys/block/<dev>/stat moved the headline
 * "scheduling headroom" figure by 45%.
 * See docs/issue_investigation/boot_cpu_saturation/README.md.
 *
 * The cost here is three lseek+read pairs per sample against already-open fds,
 * into a preallocated buffer, with one write at the end. No forks, no execs,
 * no allocation, no I/O during the measurement window.
 *
 * Three properties the shell version did not have:
 *   - no cadence drift: samples land on an absolute CLOCK_MONOTONIC grid, so a
 *     saturated core delays a sample rather than shifting every later one
 *   - it reports its own cost, from getrusage, in the output header -- so the
 *     overhead never has to be inferred again
 *   - it validates every source at startup and refuses to run if one will not
 *     parse, instead of emitting zero-filled columns that read as real data
 *
 * cross-compile:
 *   $CC --sysroot=$SYSROOT -O2 -Wall -Wextra -static \
 *       -march=armv6 -mfpu=vfp -mfloat-abi=hard -o kiosk-bootprof kiosk-bootprof.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#define MAX_SAMPLES 8192
#define RAWBUF      2048
/* First-seen time per kernel module. The question this answers: what is udev
 * loading, and in what order, in the 23s between the SDIO bus enumerating and
 * brcmfmac binding to the WiFi chip. Module loads mostly do not log, so the
 * journal cannot say. */
#define MAX_MODS    512
#define MODNAME     32

/* /proc/stat "cpu" line: user nice system idle iowait irq softirq [steal...] */
#define NCPU 7
/* /sys/block/<dev>/stat: rd_ios rd_merges rd_sec rd_ms wr_ios wr_merges
 *                        wr_sec wr_ms inflight io_ticks time_in_queue [...]  */
#define NDISK 11

struct sample {
	unsigned long long up_ns;      /* CLOCK_MONOTONIC -- same clock as journalctl -o short-monotonic */
	unsigned long long cpu[NCPU];
	unsigned long long disk[NDISK];
	unsigned int nrun;
	unsigned int nproc;
};

static struct sample samples[MAX_SAMPLES];
static unsigned int n_samples;
static unsigned int n_late;         /* samples that missed their grid slot */

struct modrec {
	char name[MODNAME];
	unsigned long long first_ns;
};
static struct modrec mods[MAX_MODS];
static unsigned int n_mods;
static int mods_overflow;

static int fd_stat = -1, fd_disk = -1, fd_load = -1, fd_mods = -1;
static const char *out_path = "/data/boot-cpu-io";
static const char *dev_name = "mmcblk0";
static unsigned int interval_ms = 1000;
static unsigned long long stop_ns;
static volatile sig_atomic_t stop_now;

static void
on_signal(int sig)
{
	(void)sig;
	stop_now = 1;
}

/* Re-read a proc/sysfs file from offset 0 into buf. Returns length, or -1. */
static ssize_t
reread(int fd, char *buf, size_t cap)
{
	ssize_t n;

	if (lseek(fd, 0, SEEK_SET) == (off_t)-1)
		return -1;
	n = read(fd, buf, cap - 1);
	if (n < 0)
		return -1;
	buf[n] = '\0';
	return n;
}

/* Parse up to want unsigned longs following prefix. Returns count parsed. */
static unsigned int
parse_ulls(const char *s, unsigned long long *out, unsigned int want)
{
	unsigned int i = 0;
	char *end;

	while (i < want) {
		while (*s == ' ' || *s == '\t')
			s++;
		if (*s < '0' || *s > '9')
			break;
		out[i++] = strtoull(s, &end, 10);
		if (end == s)
			break;
		s = end;
	}
	return i;
}

static int
read_cpu(unsigned long long *out)
{
	char buf[RAWBUF];

	if (reread(fd_stat, buf, sizeof buf) < 0)
		return -1;
	if (strncmp(buf, "cpu ", 4) != 0)
		return -1;
	return parse_ulls(buf + 4, out, NCPU) == NCPU ? 0 : -1;
}

static int
read_disk(unsigned long long *out)
{
	char buf[RAWBUF];

	if (reread(fd_disk, buf, sizeof buf) < 0)
		return -1;
	return parse_ulls(buf, out, NDISK) == NDISK ? 0 : -1;
}

/* /proc/loadavg field 4 is "<runnable>/<total>". */
static int
read_load(unsigned int *nrun, unsigned int *nproc)
{
	char buf[RAWBUF];
	const char *p;
	int spaces = 0;

	if (reread(fd_load, buf, sizeof buf) < 0)
		return -1;
	for (p = buf; *p; p++) {
		if (*p == ' ' && ++spaces == 3) {
			p++;
			break;
		}
	}
	if (spaces != 3 || *p < '0' || *p > '9')
		return -1;
	*nrun = (unsigned int)strtoul(p, (char **)&p, 10);
	if (*p != '/')
		return -1;
	*nproc = (unsigned int)strtoul(p + 1, NULL, 10);
	return 0;
}

/* Record the first time each module appears in /proc/modules. Entries are
 * appended on first sight, so discovery order is already time order. */
static void
scan_modules(unsigned long long now)
{
	static char buf[16384];
	char *p, *e;
	size_t len;
	unsigned int i;

	if (fd_mods < 0)
		return;
	if (reread(fd_mods, buf, sizeof buf) <= 0)
		return;

	for (p = buf; *p; p = e) {
		for (e = p; *e && *e != ' ' && *e != '\n'; e++)
			;
		len = (size_t)(e - p);
		if (len > 0 && len < MODNAME) {
			for (i = 0; i < n_mods; i++)
				if (mods[i].name[len] == '\0' &&
				    strncmp(mods[i].name, p, len) == 0)
					break;
			if (i == n_mods) {
				if (n_mods < MAX_MODS) {
					memcpy(mods[n_mods].name, p, len);
					mods[n_mods].name[len] = '\0';
					mods[n_mods].first_ns = now;
					n_mods++;
				} else {
					mods_overflow = 1;
				}
			}
		}
		while (*e && *e != '\n')
			e++;
		if (*e == '\n')
			e++;
	}
}

static unsigned long long
now_ns(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (unsigned long long)ts.tv_sec * 1000000000ULL +
	       (unsigned long long)ts.tv_nsec;
}

static void
flush_output(void)
{
	char path[512], line[512], bootid[64] = "unknown";
	struct rusage ru;
	unsigned long long self_us;
	unsigned int i, j;
	int fd;
	ssize_t len;

	fd = open("/proc/sys/kernel/random/boot_id", O_RDONLY);
	if (fd >= 0) {
		len = read(fd, bootid, sizeof bootid - 1);
		if (len > 0) {
			bootid[len] = '\0';
			for (i = 0; bootid[i]; i++)
				if (bootid[i] == '\n')
					bootid[i] = '\0';
		}
		close(fd);
	}

	getrusage(RUSAGE_SELF, &ru);
	self_us = (unsigned long long)ru.ru_utime.tv_sec * 1000000ULL +
	          (unsigned long long)ru.ru_utime.tv_usec +
	          (unsigned long long)ru.ru_stime.tv_sec * 1000000ULL +
	          (unsigned long long)ru.ru_stime.tv_usec;

	snprintf(path, sizeof path, "%s.%s.txt", out_path, bootid);
	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return;

	len = snprintf(line, sizeof line,
	    "# dev=%s interval=%u samples=%u late=%u self_cpu_us=%llu "
	    "first_sample_s=%.3f\n"
	    "# up user nice sys idle iowait irq softirq rd_ios rd_ms wr_ios "
	    "wr_ms inflight io_ticks nrun nproc\n",
	    dev_name, interval_ms, n_samples, n_late, self_us,
	    n_samples ? samples[0].up_ns / 1e9 : 0.0);
	if (write(fd, line, (size_t)len) != len)
		goto done;

	for (i = 0; i < n_samples; i++) {
		struct sample *s = &samples[i];

		j = (unsigned int)snprintf(line, sizeof line, "%.2f", s->up_ns / 1e9);
		/* order matches the shell sampler so the analyzer is unchanged */
		j += (unsigned int)snprintf(line + j, sizeof line - j,
		    " %llu %llu %llu %llu %llu %llu %llu",
		    s->cpu[0], s->cpu[1], s->cpu[2], s->cpu[3],
		    s->cpu[4], s->cpu[5], s->cpu[6]);
		j += (unsigned int)snprintf(line + j, sizeof line - j,
		    " %llu %llu %llu %llu %llu %llu %u %u\n",
		    s->disk[0], s->disk[3], s->disk[4], s->disk[7],
		    s->disk[8], s->disk[9], s->nrun, s->nproc);
		if (write(fd, line, j) != (ssize_t)j)
			break;
	}

	/* Module first-seen timeline, in discovery order. '#' prefixed so the
	 * sample analyzer skips it. */
	len = snprintf(line, sizeof line, "#M count=%u overflow=%d\n",
	    n_mods, mods_overflow);
	if (write(fd, line, (size_t)len) != len)
		goto done;
	for (i = 0; i < n_mods; i++) {
		len = snprintf(line, sizeof line, "#M %.2f %s\n",
		    mods[i].first_ns / 1e9, mods[i].name);
		if (write(fd, line, (size_t)len) != len)
			break;
	}
done:
	fsync(fd);
	close(fd);
}

int
main(int argc, char **argv)
{
	char diskpath[256];
	struct timespec target;
	unsigned long long start, grid;
	double duration_s = 150.0;

	if (argc > 1)
		duration_s = atof(argv[1]);
	if (argc > 2)
		interval_ms = (unsigned int)atoi(argv[2]);
	if (argc > 3)
		out_path = argv[3];
	if (argc > 4)
		dev_name = argv[4];
	if (interval_ms == 0)
		interval_ms = 1000;

	snprintf(diskpath, sizeof diskpath, "/sys/block/%s/stat", dev_name);

	fd_stat = open("/proc/stat", O_RDONLY);
	fd_disk = open(diskpath, O_RDONLY);
	fd_load = open("/proc/loadavg", O_RDONLY);
	fd_mods = open("/proc/modules", O_RDONLY);   /* optional; -1 is tolerated */
	if (fd_stat < 0 || fd_disk < 0 || fd_load < 0) {
		fprintf(stderr, "kiosk-bootprof: open failed (%s): %s\n",
		    diskpath, strerror(errno));
		return 1;
	}

	/* Refuse to run rather than emit zero-filled columns: a sampler whose
	 * broken state looks like a working one is worse than no sampler. */
	{
		unsigned long long c[NCPU], d[NDISK];
		unsigned int a, b;

		if (read_cpu(c) < 0) {
			fprintf(stderr, "kiosk-bootprof: /proc/stat cpu line "
			    "did not parse %d fields\n", NCPU);
			return 1;
		}
		if (read_disk(d) < 0) {
			fprintf(stderr, "kiosk-bootprof: %s did not parse %d "
			    "fields\n", diskpath, NDISK);
			return 1;
		}
		if (read_load(&a, &b) < 0) {
			fprintf(stderr, "kiosk-bootprof: /proc/loadavg field 4 "
			    "did not parse\n");
			return 1;
		}
	}

	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);

	start = now_ns();
	stop_ns = (unsigned long long)(duration_s * 1e9);
	grid = start;

	unsigned long long next_modscan = 0;

	while (!stop_now && n_samples < MAX_SAMPLES) {
		struct sample *s = &samples[n_samples];

		s->up_ns = now_ns();
		if (read_cpu(s->cpu) < 0 || read_disk(s->disk) < 0 ||
		    read_load(&s->nrun, &s->nproc) < 0)
			break;
		n_samples++;

		/* /proc/modules is a seq_file over every loaded module, so it
		 * costs more than the three counters above. Cap it at 1 Hz
		 * regardless of the sample interval. */
		if (s->up_ns >= next_modscan) {
			scan_modules(s->up_ns);
			next_modscan = s->up_ns + 1000000000ULL;
		}

		if (s->up_ns >= stop_ns)
			break;

		grid += (unsigned long long)interval_ms * 1000000ULL;
		if (grid <= now_ns()) {
			/* The core was too busy to keep the grid. Record it and
			 * resync rather than spinning to catch up. */
			n_late++;
			grid = now_ns() +
			    (unsigned long long)interval_ms * 1000000ULL;
		}
		target.tv_sec = (time_t)(grid / 1000000000ULL);
		target.tv_nsec = (long)(grid % 1000000000ULL);
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &target, NULL);
	}

	flush_output();
	return 0;
}
