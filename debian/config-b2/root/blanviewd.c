/*
 * blanviewd.c
 *
 * daemon to read the ambient light sensor and control
 * backlight intensity for Ortustech Blanview display
 *
 * (c) H. N. Schaller, Golden Delicious Comp. GmbH&Co. KG, 2013
 * Licence: GNU GPL2
 */

#include <stdio.h>
#include <string.h>
#include <errno.h>

struct
{
	unsigned short value;
	unsigned char backlight;
} list[]=
{
	{ 0, 100 },		// fully on
	{ 200, 100 },	// on
	// add interpolation curve values
	{ 4096, 0 },	// fully off
	{ 65535, 0 },	// fully off
};

int main(int argc, char *argv[])
{
	char debug=0;
	if(argv[1] != NULL && strcmp(argv[1], "-d") == 0)
		{
		fprintf(stderr, "debug mode\n");
		debug=1;
		}
	else if(argv[1])
		{
		fprintf(stderr, "usage: blanviewd [-d]\n");
		return 0;
		}
	while(1)
		{
		char *file="/sys/bus/i2c/drivers/tsc2007/2-0048/values";
		FILE *f=fopen(file, "r");
		int i, n;
		unsigned short x, y, pressure_raw, pressure, pendown;
		unsigned short temperature, temp0, temp1;
		unsigned short z1, z2;
		unsigned short aux;
		if(!f)
			{
			fprintf(stderr, "%s: %s\n", file, strerror(errno));
			return 1;
			}
		n=fscanf(f, "%hu,%hu,%hu,%hu,%hu,%hu,%hu,%hu,%hu,%hu,%hu", 
			   &x,
			   &y,
			   &pressure_raw,
			   &pendown,
			   &temperature,
			   &z1,
			   &z2,
			   &temp0,
			   &temp1,
			   &aux,
			   &pressure);
		fclose(f);
//		fprintf(stderr, "n=%d\n", n);
		if(n == 11)
			{
			if(debug)
				fprintf(stderr, "aux=%d", aux);
			for(i=1; i<sizeof(list)/sizeof(list[0]); i++)
				{
				if(list[i].value > aux)
					{ // found, interpolate
						long db=list[i].backlight-list[i-1].backlight;
						long dv=list[i].value-list[i-1].value;
						int bl=list[i-1].backlight+(db*aux-list[i-1].value)/dv;	// interpolate
#if 1
						file="/sys/devices/platform/pwm-backlight/backlight/pwm-backlight/brightness";
#else
						file="/sys/devices/platform/pwm-backlight/backlight/pwm-backlight/max_brightness";
#endif
						f=fopen(file, "w");
						if(!f)
							{
							fprintf(stderr, "%s: %s\n", file, strerror(errno));
							return 1;
							}
						fprintf(f, "%d\n", bl);	// set backlight level
						fclose(f);
						if(debug)
							fprintf(stderr, " -> %d\n", bl);
						break;
					}
				}
			if(!(i<sizeof(list)/sizeof(list[0])))
				fprintf(stderr, " -> ?\n");
			}
		else if(debug)
			fprintf(stderr, "n=%d\n", n);
		sleep(1);
		}
}
