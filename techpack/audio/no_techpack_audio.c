#include <linux/printk.h>
#include <linux/module.h>

#if (defined(CONFIG_TOUCHSCREEN_DOUBLETAP2WAKE) || defined(CONFIG_TOUCHSCREEN_SWEEP2WAKE))
bool gesture_incall = false;
#endif

static int no_techpack_audio_init(void)
{
	pr_info("techpack/audio isn't compiled in!");
	return 0;
}
module_init(no_techpack_audio_init)
