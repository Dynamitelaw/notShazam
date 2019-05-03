/* * Device driver for the VGA video generator
 *
 * A Platform device implemented using the misc subsystem
 *
 * Stephen A. Edwards
 * Columbia University
 *
 * References:
 * Linux source: Documentation/driver-model/platform.txt
 *               drivers/misc/arm-charlcd.c
 * http://www.linuxforu.com/tag/linux-device-drivers/
 * http://free-electrons.com/docs/
 *
 * "make" to build
 * insmod fft_accelerator.ko
 *
 * Check code style with
 * checkpatch.pl --file --no-tree fft_accelerator.c
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/errno.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/miscdevice.h>
#include <linux/slab.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include "fft_accelerator.h"


#define DRIVER_NAME "fft_accelerator"

/* Device registers */
#define TIME_COUNT(x)     (x)
//#define FREQUENCIES(x)   ((x) + 4)
#define AMPLITUDES(x)    ((x) + 4)

/*
 * Information about our device
 */
struct fft_accelerator_dev {
	struct resource res; /* Resource: our registers */
	void __iomem *virtbase; /* Where registers can be accessed in memory */
} dev;


// TODO rewrite this.  Right now it is a sketch. Double check subleties with bit widths,
// and make sure addresses match with hardware.
static void fft_accelerator_read_peaks(fft_accelerator_peaks_t *peak_struct) {
	int i;
	
	// THIS PART IS NOT FULLY PARAMETRIZED -- 
	// ioread*() calls may need to change if bit widths change.
	peak_struct->time = ioread32(TIME_COUNT(dev.virtbase) + 7); 
	for (i = 0; i < NFFT; i++) {
		//peak_struct->points[i].freq = ioread8(FREQUENCIES(dev.virtbase) + i*FREQ_WIDTH_BYTES);
		peak_struct->points[i].ampl = ioread32(AMPLITUDES(dev.virtbase) + i*AMPL_WIDTH_BYTES);
	}
}


/*
 * Handle ioctl() calls from userspace:
 * Read or write the segments on single digits.
 * Note extensive error checking of arguments
 *
 * 
 */
static long fft_accelerator_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
	fft_accelerator_peaks_t peaks;
	fft_accelerator_peaks_t *dest;
	fft_accelerator_arg_t arg_k;

	if (copy_from_user(&arg_k, (fft_accelerator_arg_t *) arg, sizeof(fft_accelerator_arg_t)))
		return -EACCES;

	switch (cmd) {

	case FFT_ACCELERATOR_READ_PEAKS:
		printk("about to read peaks\n");
		fft_accelerator_read_peaks(&peaks);
		printk("Read Peaks\n");
		dest = arg_k.peak_struct;
		printk("derefed peaks dest\n");
		if (copy_to_user(dest, &peaks,
				 sizeof(fft_accelerator_peaks_t)))
			return -EACCES;
		break;

	default:
		return -EINVAL;
	}

	return 0;
}

/* The operations our device knows how to do */
static const struct file_operations fft_accelerator_fops = {
	.owner		= THIS_MODULE,
	.unlocked_ioctl = fft_accelerator_ioctl,
};

/* Information about our device for the "misc" framework -- like a char dev */
static struct miscdevice fft_accelerator_misc_device = {
	.minor		= MISC_DYNAMIC_MINOR,
	.name		= DRIVER_NAME,
	.fops		= &fft_accelerator_fops,
};

/*
 * Initialization code: get resources (registers) and display
 * a welcome message
 */
static int __init fft_accelerator_probe(struct platform_device *pdev)
{
	int ret;

	/* Register ourselves as a misc device: creates /dev/fft_accelerator */
	ret = misc_register(&fft_accelerator_misc_device);

	/* Get the address of our registers from the device tree */
	ret = of_address_to_resource(pdev->dev.of_node, 0, &dev.res);
	if (ret) {
		ret = -ENOENT;
		goto out_deregister;
	}

	/* Make sure we can use these registers */
	if (request_mem_region(dev.res.start, resource_size(&dev.res),
			       DRIVER_NAME) == NULL) {
		ret = -EBUSY;
		goto out_deregister;
	}

	/* Arrange access to our registers */
	dev.virtbase = of_iomap(pdev->dev.of_node, 0);
	if (dev.virtbase == NULL) {
		ret = -ENOMEM;
		goto out_release_mem_region;
	}
        
	return 0;

out_release_mem_region:
	release_mem_region(dev.res.start, resource_size(&dev.res));
out_deregister:
	misc_deregister(&fft_accelerator_misc_device);
	return ret;
}

/* Clean-up code: release resources */
static int fft_accelerator_remove(struct platform_device *pdev)
{
	iounmap(dev.virtbase);
	release_mem_region(dev.res.start, resource_size(&dev.res));
	misc_deregister(&fft_accelerator_misc_device);
	return 0;
}

/* Which "compatible" string(s) to search for in the Device Tree */
#ifdef CONFIG_OF
static const struct of_device_id fft_accelerator_of_match[] = {
	{ .compatible = "csee4840,fft_accelerator-1.0" },
	{},
};
MODULE_DEVICE_TABLE(of, fft_accelerator_of_match);
#endif

/* Information for registering ourselves as a "platform" driver */
static struct platform_driver fft_accelerator_driver = {
	.driver	= {
		.name	= DRIVER_NAME,
		.owner	= THIS_MODULE,
		.of_match_table = of_match_ptr(fft_accelerator_of_match),
	},
	.remove	= __exit_p(fft_accelerator_remove),
};

/* Called when the module is loaded: set things up */
static int __init fft_accelerator_init(void)
{
	pr_info(DRIVER_NAME ": init\n");
	return platform_driver_probe(&fft_accelerator_driver, fft_accelerator_probe);
}

/* Calball when the module is unloaded: release resources */
static void __exit fft_accelerator_exit(void)
{
	platform_driver_unregister(&fft_accelerator_driver);
	pr_info(DRIVER_NAME ": exit\n");
}

module_init(fft_accelerator_init);
module_exit(fft_accelerator_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Eitan Kaplan, Columbia University");
MODULE_DESCRIPTION("FFT Accelerator driver");
