#include <stdio.h>
#include <Foundation/Foundation.h>
#include <dlfcn.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOReturn.h>
#include <sys/mount.h>
#include <sys/stat.h>

#define DEBUG_BUILD 1 // set this to 0 to disable additional logging

int (*jbclient_root_steal_ucred)(uint64_t ucredToSteal, uint64_t *orgUcred);
int64_t (*_APFSVolumeCreate)(char* device, CFMutableDictionaryRef args);
uint64_t (*_APFSVolumeDelete)(char* arg1);

uint64_t credBackup = 0;

// Thank you, khanhduytran0!
// https://gist.github.com/khanhduytran0/787e789d1630c84974773506b24d6ab3
enum {
    APFS_MOUNT_AS_ROOT = 0, /* mount the default snapshot */
    APFS_MOUNT_FILESYSTEM, /* mount live fs */
    APFS_MOUNT_SNAPSHOT, /* mount custom snapshot in apfs_mountarg.snapshot */
    APFS_MOUNT_FOR_CONVERSION, /* mount snapshot while suppling some representation of im4p and im4m */
    APFS_MOUNT_FOR_VERIFICATION, /* Fusion mount with tier 1 & 2, set by mount_apfs when -C is used (Conversion mount) */
    APFS_MOUNT_FOR_INVERSION, /* Fusion mount with tier 1 only, set by mount_apfs when -c is used */
    APFS_MOUNT_MODE_SIX,  /* ??????? */
    APFS_MOUNT_FOR_INVERT, /* ??? mount for invert */
    APFS_MOUNT_IMG4 /* mount live fs while suppling some representation of im4p and im4m */
};

struct apfs_mount_args {
    char* fspec; /* path to device to mount from */
    uint64_t apfs_flags; /* The standard mount flags, OR'd with apfs-specific flags (APFS_FLAGS_* above) */
    uint32_t mount_mode; /* APFS_MOUNT_* */
    uint32_t pad1; /* padding */
    uint32_t unk_flags; /* yet another type some sort of flags (bitfield), possibly volume role related */
    union {
        char snapshot[256]; /* snapshot name */
        struct {
            char tier1_dev[128]; /* Tier 1 device (Fusion mount) */
            char tier2_dev[128]; /* Tier 2 device (Fusion mount) */
        };
    };
    void* im4p_ptr;
    uint32_t im4p_size;
    uint32_t pad2; /* padding */
    void* im4m_ptr;
    uint32_t im4m_size;
    uint32_t pad3; /* padding */
    uint32_t cryptex_type; /* APFS_CRYPTEX_TYPE_* */
    int32_t auth_mode; /* APFS_AUTH_ENV_* */
    uid_t uid;
    gid_t gid;
}__attribute__((packed, aligned(4)));
typedef struct apfs_mount_args apfs_mount_args_t;

// Utility functions
void debug(char *format, ...) {
	va_list args;
	va_start(args, format);
	if (DEBUG_BUILD) {
		printf("[DEBUG] ");
		printf(format, args);
	}
	va_end(args);
	return;
}

char* jbrootpath() {
    NSString* preboot = @"/private/preboot/";
    NSArray* dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:preboot error:NULL];
    for (NSString *sub in dirs) {
        if ([sub length] > 20) {
            NSString* bootUUID = [preboot stringByAppendingString:sub];
            bootUUID = [bootUUID stringByAppendingString:@"/"];

            NSArray* bootUUIDManager = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bootUUID error:NULL];

            for (NSString *inBoot in bootUUIDManager) {
                if ([inBoot hasPrefix:@"dopamine-"]) {

                    NSString* dopamine = [bootUUID stringByAppendingString:inBoot];
                    NSString* jbroot = [dopamine stringByAppendingString:@"/procursus"];

                    return [jbroot UTF8String];
                }
            }
            break;
        }
    }
    return "";
}

char* getItemInJBROOT(char* item) {
    char* jbroot = jbrootpath();
    strcat(jbroot, item);
    return jbroot;
}

// main apfs mount function
int mount_apfs(const char *dir, int flags, char *device) {
	apfs_mount_args_t args = 
	{
		device, // /dev/disk0s1s8
		flags, // MNT_FORCE MNT_RDONLY MNT_UPDATE etc
		APFS_MOUNT_FILESYSTEM, // default
		0,
		0,
		{ "" },
		NULL,
		0,
		0,
		NULL,
		0,
		0,
		0,
		0,
		0,
		0
	};

	// set kernel credentials
	jbclient_root_steal_ucred(0, &credBackup);
	int ret = mount("apfs", dir, flags, &args);
	jbclient_root_steal_ucred(credBackup, NULL);
	// drop kernel credentials

	debug("mount apfs returned: %i\n", ret);
	return ret;
}

// Utility function to create apfs devices
int initialize_calls(void) {
	void* APFSHandler = dlopen("/System/Library/PrivateFrameworks/APFS.framework/APFS", RTLD_NOW);
	if (!APFSHandler) {
		printf("[-] FAIL: unable to dlopen APFS, cannot continue\n");
		dlclose(APFSHandler);
		exit(-1);
	}
	_APFSVolumeCreate = dlsym(APFSHandler, "APFSVolumeCreate");
	_APFSVolumeDelete = dlsym(APFSHandler, "APFSVolumeDelete");
	dlclose(APFSHandler);

	debug("APFS calls initialized:\nAPFSVolumeCreate: %p\nAPFSVolumeDelete: %p\n", _APFSVolumeCreate, _APFSVolumeDelete);
	
	void* LJBHandler = dlopen(getItemInJBROOT("/basebin/libjailbreak.dylib"), RTLD_NOW);
	if (!LJBHandler) {
		printf("[-] FAIL: unable to dlopen libjailbreak, cannot continue");
		dlclose(LJBHandler);
		exit(-1);
	}
	jbclient_root_steal_ucred = dlsym(LJBHandler, "jbclient_root_steal_ucred");
	dlclose(LJBHandler);
	debug("libjailbreak calls initialized:\njbclient_root_steal_ucred: %p\n", jbclient_root_steal_ucred);
	
	return 0;
}

// Utility function to get name of device
// Pass only disk0s1s8 (without /dev)
// For example: disk0s1s7 -> Preboot; /dev/disk0s1s1 -> System
char* getName(char* volume) {
	CFMutableDictionaryRef matching = IOServiceMatching("AppleAPFSVolume");
	io_iterator_t iter = 0;
	uint64_t kr = IOServiceGetMatchingServices(0, matching, &iter);

	debug("kr: %lli\n", kr);

	if (kr != KERN_SUCCESS) {
		debug("FAULT in getName in IOServiceGetMatchingServices\n");
		return nil;
	}

	io_object_t service = IOIteratorNext(iter);
	NSString* result = nil;

	while (service != 0) {
		CFStringRef dev = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("BSD Name"), nil, 0);
		if (dev) {
			NSString *devStr = (__bridge NSString *)dev;
			if ([devStr isEqualToString:[[NSString alloc] initWithUTF8String:volume]]) {
				CFStringRef name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("FullName"), nil, 0);
				if (name) {
					result = [(__bridge NSString *)name copy];
					CFRelease(name);
				}
			}
		}
		IOObjectRelease(service);
		service = IOIteratorNext(iter);
	}
	IOObjectRelease(iter);
	return [result UTF8String];
}

// Start main
// TODO: pass the action, device and moint point as arguments, will be done in other project
// Other project will be named APFSRW
int main(int argc, char *argv[], char *envp[]) {
	// BE VERY CAREFUL! DELETING ARBITARY DISK MAY CAUSE DATA LOSS!
	// I AM **NOT** RESPONSIBLE FOR **ANY** DAMAGE AND DATA LOSS CAUSED BY THIS PROGRAM
	int userchoice = 0;
	char deviceName[32];
	char device[32];
	int mountret;
	char* rootDiskDevice = "disk0s1";
	int iOS = 15;


	// Ensure functions related to Volumes management
	// Delete/Create volumes
	debug("Initializing function calls...\n");
	int calls_initialized = initialize_calls();
	debug("calls initialized; ret: %i\n", calls_initialized);

	printf("Enter iOS version (15; 16):");
	scanf("%i", &iOS);
	if (iOS == 16) {
		rootDiskDevice = "disk1";
		debug("rootDiskDevice is now %s\n", *rootDiskDevice);
	}
	printf("Welcome to apfs device utility!\n");
	printf("Enter the choice:\n 1) Create APFS device\n 2) Delete APFS device\n 3) Get name of volume\n 4) Mount partition to the directory\n 5) Force unmount device from folder with kernel privileges\n");

	printf("Enter choice: ");
	scanf("%i", &userchoice);
	if (userchoice == 1) {
		printf("Enter device name to create: "); // the name is an arbitary string
		scanf("%s", deviceName);
		printf("Going to create device with name: %s\n", deviceName);

		NSDictionary *createDict = @{@"com.apple.apfs.volume.name": [[NSString alloc] initWithUTF8String:deviceName]};

		CFMutableDictionaryRef createDictMut = CFDictionaryCreateMutableCopy(NULL, 0, (__bridge CFDictionaryRef)createDict);
		debug("Created device CFDictionary\n");
		debug("Calling _APFSVolumeCreate\n");

		int ret = _APFSVolumeCreate(rootDiskDevice, createDictMut); // specify rootDiskDevice at the top of the program
		// rootDiskDevice on iOS 15 (up to 15.8.X) is disk0s1
		// rootDiskDevice on iOS 16 (up to 16.?) is disk1

		printf("APFSVolumeCreate returned: %i\n", ret);
		if (ret == 0) {
			printf("[+] Created device\n"); // good ok
		} else {
			printf("[-] FAIL: Failed to create device"); // FAIL
		}

	} else if (userchoice == 2) {
		char deviceDisk[32];
		int AREYOUSURE = 0; // YES_I_AM_SURE
		printf("******************************************************\n");
		printf("***        ATTENTION THIS IS VERY DANGEROUS        ***\n");
		printf("***  DELETING ARBITARY DEVICE MAY CAUSE A BOOTLOOP ***\n");
		printf("***        YOU MUST KNOW WHAT YOU ARE DOING        ***\n");
		printf("******************************************************\n");
		printf("Enter device name: ");
		scanf("%s", deviceDisk);
		printf("Are you sure? This action CANNOT be undone! Enter 4277009103 to delete %s device\n", deviceDisk);
		// scanf("%i", &AREYOUSURE);
		debug("Going to delete device %s\n", deviceDisk);
		debug("Calling _APFSVolumeDelete\n");
		int ret = _APFSVolumeDelete(deviceDisk);
		printf("Deleted device: %s ret: %i\n", deviceDisk, ret);
	} else if (userchoice == 3) {
		// Get the name of specified device (enter device in format disk0s1s1 - without /dev prefix)
		printf("Enter device: ");
		scanf("%s", device);
		printf("\n");
		char* volName = getName(device);
		printf("Name of %s device: %s\n", device, volName);
		return 0;
	} else if (userchoice == 4) {
		// The arguments for mounting APFS is real hell
		char device[32];
		char mountPoint[32]; 
		printf("Enter device: "); // device should be with /dev prefix
		scanf("%s", device);
		printf("Enter mount point: "); // This is a directory to mount apfs over
		scanf("%s", mountPoint);
		
		printf("Mounting %s on %s\n", device, mountPoint);
		 
		// Finally, arbitary mount_apfs!
		int ret = mount_apfs(mountPoint, MNT_FORCE, device);
		printf("mount_apfs returned: %i\n", ret);
	} else if (userchoice == 5) {
		char path[PATH_MAX+1];
		printf("Enter folder to unmount: ");
		scanf("%s", path);
		printf("Unmounting: %s\n", path);
		debug("Giving kernel privileges\n");
		jbclient_root_steal_ucred(0, &credBackup);
		int ret = unmount(path, MNT_FORCE);
		jbclient_root_steal_ucred(credBackup, NULL);
		debug("Dropping kernel privileges\n");
		printf("unmount returned: %i\n", ret);

	} else if (userchoice > 4 || userchoice == 0) {
		// what do you mean?
		printf("Enter supported action\n");
		return -1;
	}
	return 0;
}