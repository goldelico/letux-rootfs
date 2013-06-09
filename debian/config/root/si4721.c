/********************************************************************** 
 si4721 userspace quickhack - Copyright (C) 2012 - Andreas Kemnade
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3, or (at your option)
 any later version.
             
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
***********************************************************************/

#include <sys/ioctl.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#define I2CADDR 0x11

static int fd=-1;
/* sends a command to the si4721 chip and gets a response */
static int send_cmd(unsigned char *cmd_data,int cmd_len,unsigned char *resp_data, int resp_len)
{
  struct i2c_rdwr_ioctl_data iod;
  struct i2c_msg msgs[2];
  if (resp_data)
    iod.nmsgs=2;
  else
    iod.nmsgs=1;
  iod.msgs=msgs;
  msgs[0].addr=I2CADDR;
  msgs[0].flags=0;
  msgs[0].buf=cmd_data;
  msgs[0].len=cmd_len;
  msgs[1].addr=I2CADDR;
  msgs[1].flags=I2C_M_RD;
  msgs[1].buf=resp_data;
  msgs[1].len=resp_len;
  return (0<=ioctl(fd,I2C_RDWR,&iod)); 
}

int main(int argc, char **argv)
{
  unsigned char resp[16];
  unsigned char tune[5];
  int i;
  int freq;
  if ((argc != 3) && (argc !=4)) {
    fprintf(stderr,"Usage: %s /dev/i2c-X freq-in-10khz [srate]\neg: %s /dev/i2c-2 9380 for 93800khz\n",argv[0],argv[0]);
    return 1;
  }
  fd=open(argv[1],O_RDWR);
  if (fd<0) {
    fprintf(stderr," cannot open i2c\n");
    return 1;
  }
  freq=atoi(argv[2]);
  /* set frequency */
  tune[0]=0x20;
  tune[1]=0;
  tune[2]=freq/256;
  tune[3]=freq&255;
  tune[4]=0;
  /* power on command */
  if (freq == 0) {
    send_cmd("\x11",1,resp,1);
    return 0;
  } 
  send_cmd("\x01\x00\xb0",3,resp,1); 
  sleep(1);
  /* get revision */
  printf("init resp: %02x\n",(int)resp[0]);
  send_cmd("\x10",1,resp,16);
  sleep(1);
  printf("get_chiprev resp: %02x\n",(int)resp[0]);
  for(i=1;i<16;i++) {
    printf("%02x",resp[i]);
  } 
  printf("\n");
  /* set the frequency */
  send_cmd(tune,5,resp,1);
  sleep(1);
  printf("tune freq: %02x\n",(int)resp[0]);
  sleep(1);
  /* tune status */
  send_cmd("\x22\x00",2,resp,8);
  printf("tune status resp: %02x\n",(int)resp[0]);
  printf("tuned to %d0khz RSSI %d SNR %d",((int)resp[2])*256+resp[3], (int)resp[4],(int)resp[5]);
  if (resp[1]&1)
    printf(" valid signal!\n");
  else {
    printf(" no signal\n");
  }
  /* set sampling rate property */
  if (argc==4) { 
    int f;
    unsigned char prop[5];
    f=atoi(argv[3]);
    prop[0]=0x12;
    prop[1]=0;
    prop[2]=0x01;
    prop[3]=0x02;
    prop[4]=0;
    prop[5]=128; 
    send_cmd(prop,6,NULL,0);
    prop[3]=0x04;
    prop[4]=f/256;
    prop[5]=f&255;
    send_cmd(prop,6,NULL,0);
  }
  while(1) {
   /* query tune status */
    send_cmd("\x23\x00",2,resp,8);
    printf("tune rsq resp: %02x\n",(int)resp[0]);
    printf("RSSI %d SNR %d", (int)resp[4],(int)resp[5]);
    if (resp[2]&1) {
      printf(" valid signal!\n");
    } else {
      printf(" no signal\n");
    }
    for(i=1;i<8;i++) {
      printf("%02x",resp[i]);
    } 
    printf("\n");
    sleep(1);
  }
  
  return 0;
}
