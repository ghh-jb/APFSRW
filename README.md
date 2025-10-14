# APFSRW
This tool is used to do some staff with APFS - Apple File System
Was made to add rootful support for Dopamine giving user access to the subfolders of RootFS, however there are some unresolved issues on iOS 16.
Special thanks to [Duy Tran](https://github.com/khanhduytran0) for APFS mount args.

# WARNING - ONLY FOR DEVELOPERS
This is currently in beta. There may be issues that I've never experienced. But feel free to open an issue or PR.

# Tested partitions and iOS Versions
- iPhone 11: iOS 16.3.1
- iPhone SE 2016: iOS 15.8.4

# Building
You need to have theos installed.
Download 15.2 sdk or specify your own in the ```Makefile``` and then run ```make package``` in the projeect directory.

# Installing
Locate built .deb in the packages directory and install it on partition via dpkg/Sileo.

# How to use
The tool is shipped with 5 different features:
1. Create APFS partition (for example /dev/disk0s1s8)
2. Delete APFS partition
3. Get name of APFS partition
4. Mount partition to a folder with kernel privilegies
5. Force unmount partition from folder with kernel privilegies

("With kernel privilegies" mean you can mount partitions over /Applications, /usr or /
Library for example, and so unmount)

**APFS partition creation**
After launching the tool and selecting 1 you will be asked for a name of volume. Just enter the name and hit enter. After that you will have a new `/dev/disk0s1sX` (on iOS 15) and `/dev/disk1sX` (on iOS 16) created. You can try to mount it to `/var/mnt/APFStest` for example using stock mount_apfs tool.

**APFS partition removing**
IF you created too much APFS partitions, you can delete some of them, but remember:
***IT IS EXTREMELY DANGEROUS TO USE THIS FEATURE IF YOU DONT KNOW HOW TO USE IT***
After launching the tool and selecting 2 you will be warned and then promted for a partition to delete. 
Remember:
***EVERY TIME YOU DELETE A partition - FIRST CHECK IF IT IS A partition YOU CREATED***
***DELETING WRONG VOLUME MAY CAUSE A BOOTLOOP***
Enter partition name with /dev prefix (for example /dev/disk0s1s14) and it will be deleted.

***APFS partition name getter***
After launching the tool and selecting 3 you woll be asked for partition name, enter partition WITHOUT /dev prefix. Maybe i will fix it later.
Simply gets name of APFS partition. 
On iOS 15: /dev/disk0s1s1 -> System
		   /dev/disk0s1s7 -> Preboot
		   /dev/disk0s1s8 -> Fugu15App
		   /dev/disk0s1s9 -> Fugu15Bin
And others. Will maybe add safety checks based on volume name later.

***APFS partition mounter***
After launching the tool and selecting 4 you will be asked for partition name, specify full path to the partition (including /dev prefix), hit enter and then specify a folder, over what to mount the partition. Folder MUST exist or else mounting will fail. 
Calls mount() function programmatically with `apfs_args_t` as the last argument (void*).
Using this method we can mount partition to any location on the file system, even over the protected ones like `/Applcations`, `/sbin`, `/usr` because we set kernel ucred before calling mount(). This did **NOT** corrupt uicache on all of my 3 iPhones.
Using this function combined with first APFSVolumeCreate you can get rootful jailbreak out of rootless on iOS 15. 

***APFS partition unmounter***
After launching the tool and selecting 4 you will be asked for the path, where the disk is mounted. You should specify the full path to the directory. 
Calls unmount() with MNT_FORCE flag. Also sets kernel ucred before calling unmount(), so if you accidently mounted /dev/disk0s1sX over /Library and it is now empty, just use this option.

# Safety tips
(Accidents hurt, safety doesn't)
So, to begin with:

**uicache**
Especially important if you mount a partition over /Applications
- don't install applications with same bundle identifiers in different places of the system. For example, if you have Filza installed via trollstore and then you copy Filza to /Applications, after running `uicache -a` you may (or may not?) corrupt your icon cache, after that SpringBoard will stob loading, crashing on startup and you will get a bootloop.

**More to be added??**

# License
GNU GENERAL PUBLIC LICENSE Version 3. See the ```LICENSE``` file.