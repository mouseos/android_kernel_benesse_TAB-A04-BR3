// SPDX-License-Identifier: GPL-2.0
/* Receive-only MT6630 FM smoke test for A04BR3. */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define FM_IOC_MAGIC 0xf5

struct fm_tune_parm {
	uint8_t err;
	uint8_t band;
	uint8_t space;
	uint8_t hilo;
	uint8_t deemphasis;
	uint16_t freq;
};

struct fm_ctl_parm {
	uint8_t err;
	uint8_t addr;
	uint16_t val;
	uint16_t rw_flag;
};

struct fm_i2s_info {
	int32_t status;
	int32_t mode;
	int32_t rate;
};

struct fm_audio_info {
	int32_t path;
	struct fm_i2s_info i2s;
	int32_t pad;
};

struct fm_softmute_tune {
	int32_t rssi;
	uint16_t freq;
	int32_t valid;
};

#define FM_IOCTL_POWERUP _IOWR(FM_IOC_MAGIC, 0, struct fm_tune_parm *)
#define FM_IOCTL_POWERDOWN _IOWR(FM_IOC_MAGIC, 1, int32_t *)
#define FM_IOCTL_GETRSSI _IOWR(FM_IOC_MAGIC, 7, int32_t *)
#define FM_IOCTL_GETCHIPID _IOWR(FM_IOC_MAGIC, 10, uint16_t *)
#define FM_IOCTL_RW_REG _IOWR(FM_IOC_MAGIC, 12, struct fm_ctl_parm *)
#define FM_IOCTL_GETMONOSTERO _IOWR(FM_IOC_MAGIC, 13, uint16_t *)
#define FM_IOCTL_GETCURPAMD _IOWR(FM_IOC_MAGIC, 14, uint16_t *)
#define FM_IOCTL_GET_I2S_INFO _IOWR(FM_IOC_MAGIC, 41, struct fm_i2s_info *)
#define FM_IOCTL_GET_AUDIO_INFO _IOWR(FM_IOC_MAGIC, 48, struct fm_audio_info *)
#define FM_IOCTL_SOFT_MUTE_TUNE _IOWR(FM_IOC_MAGIC, 63, struct fm_softmute_tune *)

static void dump_register(int fd, uint8_t addr)
{
	struct fm_ctl_parm ctl = {
		.addr = addr,
		.rw_flag = 1,
	};

	if (ioctl(fd, FM_IOCTL_RW_REG, &ctl) < 0)
		fprintf(stderr, "reg[0x%02x]: %s\n", addr, strerror(errno));
	else
		printf("reg[0x%02x]=0x%04x\n", addr, ctl.val);
}

static void dump_receiver_state(int fd, uint16_t frequency)
{
	static const uint8_t registers[] = {
		0x56, 0x5f, 0x60, 0x61, 0x63, 0x64,
		0x65, 0x69, 0x6a, 0x6b, 0x6c, 0x6f, 0x9b,
	};
	struct fm_audio_info audio = { 0 };
	struct fm_i2s_info i2s = { 0 };
	struct fm_softmute_tune softmute = {
		.freq = frequency,
	};
	uint16_t stereo = 0;
	uint16_t pamd = 0;
	size_t i;

	for (i = 0; i < sizeof(registers); i++)
		dump_register(fd, registers[i]);

	if (ioctl(fd, FM_IOCTL_GETMONOSTERO, &stereo) < 0)
		perror("FM_IOCTL_GETMONOSTERO");
	else
		printf("stereo=%u\n", stereo);
	if (ioctl(fd, FM_IOCTL_GETCURPAMD, &pamd) < 0)
		perror("FM_IOCTL_GETCURPAMD");
	else
		printf("pamd=%u\n", pamd);
	if (ioctl(fd, FM_IOCTL_GET_I2S_INFO, &i2s) < 0)
		perror("FM_IOCTL_GET_I2S_INFO");
	else
		printf("i2s status=%d mode=%d rate=%d\n",
		       i2s.status, i2s.mode, i2s.rate);
	if (ioctl(fd, FM_IOCTL_GET_AUDIO_INFO, &audio) < 0)
		perror("FM_IOCTL_GET_AUDIO_INFO");
	else
		printf("audio path=%d pad=%d i2s-status=%d mode=%d rate=%d\n",
		       audio.path, audio.pad, audio.i2s.status,
		       audio.i2s.mode, audio.i2s.rate);
	if (ioctl(fd, FM_IOCTL_SOFT_MUTE_TUNE, &softmute) < 0)
		perror("FM_IOCTL_SOFT_MUTE_TUNE");
	else
		printf("cqi freq=%u.%u MHz rssi=%d valid=%d\n",
		       softmute.freq / 100, softmute.freq % 100,
		       softmute.rssi, softmute.valid);
}

int main(int argc, char **argv)
{
	long requested = 8000;
	long hold_seconds = 0;
	struct fm_tune_parm tune = {
		.band = 3, /* Japan wide band, 76.0-108.0 MHz */
		.space = 1,
	};
	int32_t powerdown_type = 0;
	int32_t rssi = 0;
	uint16_t chip_id = 0;
	int fd;
	int ret = EXIT_FAILURE;

	if (argc > 1) {
		char *end;

		errno = 0;
		requested = strtol(argv[1], &end, 10);
		if (errno || *end || requested < 7600 || requested > 10800) {
			fprintf(stderr, "frequency must be in 10 kHz units (7600-10800)\n");
			return EXIT_FAILURE;
		}
	}
	tune.freq = (uint16_t)requested;
	if (argc > 2) {
		char *end;

		errno = 0;
		hold_seconds = strtol(argv[2], &end, 10);
		if (errno || *end || hold_seconds < 0 || hold_seconds > 3600) {
			fprintf(stderr, "hold time must be in seconds (0-3600)\n");
			return EXIT_FAILURE;
		}
	}

	fd = open("/dev/fm", O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open /dev/fm");
		return EXIT_FAILURE;
	}

	if (ioctl(fd, FM_IOCTL_POWERUP, &tune) < 0) {
		perror("FM_IOCTL_POWERUP");
		if (hold_seconds) {
			printf("holding failed power-up state for %ld seconds\n",
			       hold_seconds);
			fflush(stdout);
			sleep((unsigned int)hold_seconds);
		}
		goto powerdown;
	}
	printf("tuned=%u.%u MHz status=%u\n", tune.freq / 100,
	       tune.freq % 100, tune.err);

	if (ioctl(fd, FM_IOCTL_GETCHIPID, &chip_id) < 0) {
		perror("FM_IOCTL_GETCHIPID");
		goto powerdown;
	}
	if (ioctl(fd, FM_IOCTL_GETRSSI, &rssi) < 0) {
		perror("FM_IOCTL_GETRSSI");
		goto powerdown;
	}
	printf("chip=0x%04x rssi=%d\n", chip_id, rssi);
	dump_receiver_state(fd, tune.freq);
	if (hold_seconds) {
		printf("holding receiver on for %ld seconds\n", hold_seconds);
		fflush(stdout);
		sleep((unsigned int)hold_seconds);
	}
	ret = EXIT_SUCCESS;

powerdown:
	if (ioctl(fd, FM_IOCTL_POWERDOWN, &powerdown_type) < 0) {
		perror("FM_IOCTL_POWERDOWN");
		ret = EXIT_FAILURE;
	}
	close(fd);
	return ret;
}
