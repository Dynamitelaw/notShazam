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

#include <linux/delay.h>
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
#define AMPLITUDES(x)    (x) 
#define TIME_COUNT(x)    (AMPLITUDES(x) + AMPLITUDES_SIZE)
#define VALID(x)         (TIME_COUNT(x) + COUNTER_WIDTH_BYES) 
#define READING(x)       (VALID(x) + 1)

/*
 * Information about our device
 */
struct fft_accelerator_dev {
	struct resource res; /* Resource: our registers */
	void __iomem *virtbase; /* Where registers can be accessed in memory */
} dev;


// TODO rewrite this.  Right now it is a sketch. Double check subleties with bit widths,
// and make sure addresses match with hardware.
static int fft_accelerator_read_sample(fft_accelerator_fft_t *sample_struct) {
	int i;
	static uint32_t prev_time = 0;
	
	// THIS PART IS NOT FULLY PARAMETRIZED -- 
	// ioread*() calls may need to change if bit widths change.
	int tries = 0;
	while (1) {
		while ((sample_struct->time = ioread32(TIME_COUNT(dev.virtbase))) == prev_time) {
			tries++;
			if (tries > 15){
				return -1;
			}
			usleep_range(1000, 2000);
		}
		iowrite8(0x1u, READING(dev.virtbase));
		for (i = 0; i < N_FREQUENCIES; i++) {
			sample_struct->fft[i] = ioread32(AMPLITUDES(dev.virtbase) + i*AMPL_WIDTH_BYTES);
		}
		sample_struct->valid = ioread8(VALID(dev.virtbase)); 
		iowrite8(0x0u, READING(dev.virtbase));
		if (sample_struct->valid){
			break;
		} else {
			tries++;
		}
	}
	printk("\tSample time delta: %d\n", sample_struct->time - prev_time);
	prev_time = sample_struct->time;
	return 0;
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
	fft_accelerator_fft_t *sample;
	fft_accelerator_fft_t *dest;
	fft_accelerator_arg_t arg_k;

	if (copy_from_user(&arg_k, (fft_accelerator_arg_t *) arg, sizeof(fft_accelerator_arg_t)))
		return -EACCES;

	switch (cmd) {

	case FFT_ACCELERATOR_READ_FFT:
		sample = kmalloc(sizeof(fft_accelerator_fft_t), GFP_KERNEL);
		if (sample == NULL) {
			printk("nomem");
			return -ENOMEM;
		}
		printk("About to read sample\n");
		if (fft_accelerator_read_sample(sample) == -1) {
			kfree(sample);			
			return -EIO;
		}
		printk("Read Peaks\n");
		dest = arg_k.fft_struct;
		if (copy_to_user(dest, sample,
				 sizeof(fft_accelerator_fft_t))) {
			kfree(sample);			
			return -EACCES;
		}
		kfree(sample);
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
