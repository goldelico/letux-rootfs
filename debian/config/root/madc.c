/* read all MADC channels and report , separated values */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <fcntl.h>

typedef uint8_t u8;
typedef uint16_t u16;

#define TWL4030_MADC_IOC_MAGIC '`'
#define TWL4030_MADC_IOCX_ADC_RAW_READ		_IO(TWL4030_MADC_IOC_MAGIC, 0)

void channel(int fd, int i)
{
	struct twl4030_madc_user_parms
	{
	int channel;
	int average;
	int status;
	u16 result;
	} param= {
		i,
		0,
		0,
		0 };
	if(ioctl(fd, TWL4030_MADC_IOCX_ADC_RAW_READ, &param) < 0)
		{
		perror("ioctl");
		exit(1);
		}
	if(i > 0)
		printf(",");
	if(param.status == -1)
		printf("-1");
	else
		printf("%d", param.result);
}

int main(int argc, char **argv)
{
	int fd=open("/dev/twl4030-madc", O_RDWR, 0);
	int i;
	if(fd < 0)
		{
		perror("open");
		exit(1);
		}
	for(i=0; i<16; i++)
		channel(fd, i);
	printf("\n");
	close(fd);
	return 0;
}
