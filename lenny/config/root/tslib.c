/*
 * (c) 2006 Sascha Hauer, Pengutronix <s.hauer@pengutronix.de>
 *
 * 20070416 Support for rotated displays by
 *          Clement Chauplannaz, Thales e-Transactions <chauplac@gmail.com>
 *
 * derived from the xf86-input-void driver
 * Copyright 1999 by Frederic Lepied, France. <Lepied@XFree86.org>
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is  hereby granted without fee, provided that
 * the  above copyright   notice appear  in   all  copies and  that both  that
 * copyright  notice   and   this  permission   notice  appear  in  supporting
 * documentation, and that   the  name of  Frederic   Lepied not  be  used  in
 * advertising or publicity pertaining to distribution of the software without
 * specific,  written      prior  permission.     Frederic  Lepied   makes  no
 * representations about the suitability of this software for any purpose.  It
 * is provided "as is" without express or implied warranty.
 *
 * FREDERIC  LEPIED DISCLAIMS ALL   WARRANTIES WITH REGARD  TO  THIS SOFTWARE,
 * INCLUDING ALL IMPLIED   WARRANTIES OF MERCHANTABILITY  AND   FITNESS, IN NO
 * EVENT  SHALL FREDERIC  LEPIED BE   LIABLE   FOR ANY  SPECIAL, INDIRECT   OR
 * CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
 * DATA  OR PROFITS, WHETHER  IN  AN ACTION OF  CONTRACT,  NEGLIGENCE OR OTHER
 * TORTIOUS  ACTION, ARISING    OUT OF OR   IN  CONNECTION  WITH THE USE    OR
 * PERFORMANCE OF THIS SOFTWARE.
 *
 */

/* tslib input driver */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#ifndef XFree86LOADER
#include <unistd.h>
#include <errno.h>
#endif

#include <misc.h>
#include <xf86.h>
#if !defined(DGUX)
#include <xisb.h>
#endif
#include <xf86_OSproc.h>
#include <xf86Xinput.h>
#include <exevents.h>		/* Needed for InitValuator/Proximity stuff */
#include <X11/keysym.h>
#include <mipointer.h>

#include <tslib.h>

#ifdef XFree86LOADER
#include <xf86Module.h>
#endif

#define MAXBUTTONS 1

#define DEFAULT_HEIGHT		240
#define DEFAULT_WIDTH		320

enum { TSLIB_ROTATE_NONE=0, TSLIB_ROTATE_CW=270, TSLIB_ROTATE_UD=180, TSLIB_ROTATE_CCW=90 };

struct ts_priv {
	XISBuffer *buffer;
	struct tsdev *ts;
	int lastx,lasty,lastp;
	int screen_num;
	int rotate;
	int height;
	int width;
};

static const char *DEFAULTS[] = {
	"TslibDevice", "/dev/event0",
	NULL
};

static void
BellProc(int percent, DeviceIntPtr pDev, pointer ctrl, int unused)
{
	ErrorF("%s\n", __FUNCTION__);
	return;
}

static void
KeyControlProc(DeviceIntPtr pDev, KeybdCtrl * ctrl)
{
	ErrorF("%s\n", __FUNCTION__);
	return;
}

static void
PointerControlProc(DeviceIntPtr dev, PtrCtrl * ctrl)
{
	ErrorF("%s\n", __FUNCTION__);
	return;
}

static Bool
ConvertProc( LocalDevicePtr local,
			 int first,
			 int num,
			 int v0,
			 int v1,
			 int v2,
			 int v3,
			 int v4,
			 int v5,
			 int *x,
			 int *y )
{
	*x = v0;
	*y = v1;
	return TRUE;
}

static void ReadInput (LocalDevicePtr local)
{
	struct ts_priv *priv = (struct ts_priv *) (local->private);
	struct ts_sample samp;
	int ret;
	int x,y;

	ret = ts_read(priv->ts, &samp, 1);

	if (ret < 0) {
		ErrorF("ts_read failed\n");
		return;
	}

//	ErrorF("%ld.%06ld: %6d %6d %6d\n", samp.tv.tv_sec, samp.tv.tv_usec, samp.x, samp.y, samp.pressure);

	if(samp.pressure) {
		int tmp_x = samp.x;

		switch(priv->rotate) {
		case TSLIB_ROTATE_CW:	samp.x = samp.y;
					samp.y = priv->width - tmp_x;
					break;
		case TSLIB_ROTATE_UD:	samp.x = priv->width - samp.x;
					samp.y = priv->height - samp.y;
					break;
		case TSLIB_ROTATE_CCW:	samp.x = priv->height - samp.y;
					samp.y = tmp_x;
					break;
		default:		break;
		}

		priv->lastx = samp.x;
		priv->lasty = samp.y;
		x = samp.x;
		y = samp.y;

		xf86XInputSetScreen(local, priv->screen_num,
				samp.x,
				samp.y);

		xf86PostMotionEvent (local->dev, TRUE, 0, 2,
				x, y);

	}

	if(priv->lastp != samp.pressure) {
		priv->lastp = samp.pressure;

		xf86PostButtonEvent(local->dev, TRUE,
			1, !!samp.pressure, 0, 2,
			priv->lastx,
			priv->lasty);
	}

}

/*
 * xf86TslibControlProc --
 *
 * called to change the state of a device.
 */
static int
xf86TslibControlProc(DeviceIntPtr device, int what)
{
	InputInfoPtr pInfo;
	unsigned char map[MAXBUTTONS + 1];
	int i, axiswidth, axisheight;
	struct ts_priv *priv;

	ErrorF("%s\n", __FUNCTION__);
	pInfo = device->public.devicePrivate;
	priv = pInfo->private;

	switch (what) {
	case DEVICE_INIT:
		device->public.on = FALSE;

		for (i = 0; i < MAXBUTTONS; i++) {
			map[i + 1] = i + 1;
		}

		if (InitButtonClassDeviceStruct(device,
						MAXBUTTONS, map) == FALSE) {
			ErrorF("unable to allocate Button class device\n");
			return !Success;
		}

		if (InitValuatorClassDeviceStruct(device,
						  2,
						  xf86GetMotionEvents,
						  0, Absolute) == FALSE) {
			ErrorF("unable to allocate Valuator class device\n");
			return !Success;
		}

		switch(priv->rotate) {
			case TSLIB_ROTATE_CW:
			case TSLIB_ROTATE_CCW:
				axiswidth = priv->height;
				axisheight = priv->width;
				break;
			default:
				axiswidth = priv->width;
				axisheight = priv->height;
				break;
		}
			
		InitValuatorAxisStruct(device, 0, 0,    	/* min val */
					       axiswidth - 1,	/* max val */
					       axiswidth,	/* resolution */
					       0,		/* min_res */
					       axiswidth);	/* max_res */

		InitValuatorAxisStruct(device, 1, 0,    	/* min val */
					       axisheight - 1,/* max val */
					       axisheight,	/* resolution */
					       0,		/* min_res */
					       axisheight);	/* max_res */

		if (InitProximityClassDeviceStruct (device) == FALSE) {
			ErrorF ("Unable to allocate EVTouch touchscreen ProximityClassDeviceStruct\n");
			return !Success;
		}

		/* allocate the motion history buffer if needed */
#if GET_ABI_MAJOR(ABI_XINPUT_VERSION) == 0
		xf86MotionHistoryAllocate(pInfo);
#endif

		break;

	case DEVICE_ON:
		AddEnabledDevice(pInfo->fd);

		device->public.on = TRUE;
		break;

	case DEVICE_OFF:
	case DEVICE_CLOSE:
		device->public.on = FALSE;
		break;
	}
	return Success;
}

/*
 * xf86TslibUninit --
 *
 * called when the driver is unloaded.
 */
static void
xf86TslibUninit(InputDriverPtr drv, InputInfoPtr pInfo, int flags)
{
	ErrorF("%s\n", __FUNCTION__);
	xf86TslibControlProc(pInfo->dev, DEVICE_OFF);
	xfree(pInfo->private);
}

/*
 * xf86TslibInit --
 *
 * called when the module subsection is found in XF86Config
 */
static InputInfoPtr
xf86TslibInit(InputDriverPtr drv, IDevPtr dev, int flags)
{
	struct ts_priv *priv;
	char *s;
	InputInfoPtr pInfo;

	priv = xcalloc (1, sizeof (struct ts_priv));
        if (!priv)
                return NULL;

	if (!(pInfo = xf86AllocateInput(drv, 0))) {
		xfree(priv);
		return NULL;
	}

	/* Initialise the InputInfoRec. */
	pInfo->name = dev->identifier;
	pInfo->type_name = XI_TOUCHSCREEN;
	pInfo->flags =
	    XI86_KEYBOARD_CAPABLE | XI86_POINTER_CAPABLE |
	    XI86_SEND_DRAG_EVENTS;
	pInfo->device_control = xf86TslibControlProc;
	pInfo->read_input = ReadInput;
#if GET_ABI_MAJOR(ABI_XINPUT_VERSION) == 0
	pInfo->motion_history_proc = xf86GetMotionEvents;
	pInfo->history_size = 0;
#endif
	pInfo->control_proc = NULL;
	pInfo->close_proc = NULL;
	pInfo->switch_mode = NULL;
	pInfo->conversion_proc = ConvertProc;
	pInfo->reverse_conversion_proc = NULL;
	pInfo->dev = NULL;
	pInfo->private_flags = 0;
	pInfo->always_core_feedback = 0;
	pInfo->conf_idev = dev;
	pInfo->private = priv;

	/* Collect the options, and process the common options. */
	xf86CollectInputOptions(pInfo, DEFAULTS, NULL);
	xf86ProcessCommonOptions(pInfo, pInfo->options);

	priv->screen_num = xf86SetIntOption(pInfo->options, "ScreenNumber", 0 );

	priv->width = xf86SetIntOption(pInfo->options, "Width", 0);
	if (priv->width <= 0)	priv->width = DEFAULT_WIDTH;

	priv->height = xf86SetIntOption(pInfo->options, "Height", 0);
	if (priv->height <= 0)	priv->height = DEFAULT_HEIGHT;

	s = xf86SetStrOption(pInfo->options, "Rotate", 0);
	if (s > 0) {
		if (strcmp(s, "CW") == 0) {
			priv->rotate = TSLIB_ROTATE_CW;
		} else if (strcmp(s, "UD") == 0) {
			priv->rotate = TSLIB_ROTATE_UD;
		} else if (strcmp(s, "CCW") == 0) {
			priv->rotate = TSLIB_ROTATE_CCW;
		} else {
			priv->rotate = TSLIB_ROTATE_NONE;
		}
	} else {
		priv->rotate = TSLIB_ROTATE_NONE;
	}

	s = xf86SetStrOption(pInfo->options, "TslibDevice", NULL);

	priv->ts = ts_open(s, 0);
	if (!priv->ts) {
		ErrorF("ts_open failed (device=%s)\n",s);
		return NULL;
	}

	xfree(s);

	if (ts_config(priv->ts)) {
		ErrorF("ts_config failed\n");
		return NULL;
	}

	pInfo->fd = ts_fd(priv->ts);

	/* Mark the device configured */
	pInfo->flags |= XI86_CONFIGURED;

	/* Return the configured device */
	return (pInfo);
}

_X_EXPORT InputDriverRec TSLIB = {
	1,			/* driver version */
	"tslib",		/* driver name */
	NULL,			/* identify */
	xf86TslibInit,		/* pre-init */
	xf86TslibUninit,	/* un-init */
	NULL,			/* module */
	0			/* ref count */
};

/*
 ***************************************************************************
 *
 * Dynamic loading functions
 *
 ***************************************************************************
 */
#ifdef XFree86LOADER

/*
 * xf86TslibUnplug --
 *
 * called when the module subsection is found in XF86Config
 */
static void xf86TslibUnplug(pointer p)
{
}

/*
 * xf86TslibPlug --
 *
 * called when the module subsection is found in XF86Config
 */
static pointer xf86TslibPlug(pointer module, pointer options, int *errmaj, int *errmin)
{
	static Bool Initialised = FALSE;

	xf86AddInputDriver(&TSLIB, module, 0);

	return module;
}

static XF86ModuleVersionInfo xf86TslibVersionRec = {
	"tslib",
	MODULEVENDORSTRING,
	MODINFOSTRING1,
	MODINFOSTRING2,
	XORG_VERSION_CURRENT,
	0, 0, 1,
	ABI_CLASS_XINPUT,
	ABI_XINPUT_VERSION,
	MOD_CLASS_XINPUT,
	{0, 0, 0, 0}		/* signature, to be patched into the file by */
	/* a tool */
};

_X_EXPORT XF86ModuleData tslibModuleData = {
	&xf86TslibVersionRec,
	xf86TslibPlug,
	xf86TslibUnplug
};

#endif				/* XFree86LOADER */

/*
 * Local variables:
 * change-log-default-name: "~/xinput.log"
 * c-file-style: "bsd"
 * End:
 */
/* end of tslib.c */
