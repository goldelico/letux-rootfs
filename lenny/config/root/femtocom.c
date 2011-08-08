/* femtocom.c - gcc -o femtocom femtocom.c */

#include <unistd.h>
#include <fcntl.h>
#include <sys/select.h>

main(int argc, char *argv[])
{
	int fd;
	if(!argv[1])
		{
		fprintf(stderr, "usage: %s /dev/ttyHS?", argv[0]);
		return 1;
		}
	fd=open(argv[1], O_RDWR);
	if(fd < 0)
		return 1;
	while(1)
		{
		fd_set rfd, wfd, efd;
		FD_SET(0, &rfd);
		FD_SET(fd, &rfd);
		FD_SET(1, &wfd);
		FD_SET(fd, &wfd);
		if(select(fd+1, &rfd, &wfd, &efd, NULL) > 0)
			{
			char buf[1];
			if(FD_ISSET(0, &rfd) && FD_ISSET(fd, &wfd))
				{ /* echo stdin -> tty */
				int n=read(0, buf, 1);
				if(n  < 0)
					return 2;
				if(n == 0)
					return 0;	/* EOF */
				write(fd, buf, n);
				}
			if(FD_ISSET(fd, &rfd) && FD_ISSET(1, &wfd))
				{ /* echo tty -> stdout */
				int n=read(fd, buf, 1);
				if(n  < 0)
					return 3;
				if(n > 0)
					write(1, buf, n);
				}
			}
		}
}
