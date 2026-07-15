# NVIDIA Jetson Thor / JetPack docs index (URL catalog)

Scraped **2026-07-15** from:
- [Jetson Thor product](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-thor/)
- [JetPack SDK](https://developer.nvidia.com/embedded/jetpack)
- [Jetson Linux Developer Guide r39.2](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/) (Sphinx inventory; Thor + Orin)

## How to use this file

1. Skim summaries (or search this file) to find the right page.
2. **Fetch the live URL** for full procedures, commands, and tables — do not invent flashing/BSP steps from the summary alone.
3. Camp Thors are Jetson Thor / AGX Thor class devices on JetPack / Jetson Linux **r39.x** — prefer Thor-tagged pages when both Thor and Orin variants exist.
4. Related camp notes live in skill refs (`docker-build-deploy.md`, Thor CUDA/`/dev/nvmap`, pluginctl GPU tips).

**Pages indexed:** 192

## Thor-focused pages (quick list)

- [Jetson Thor Boot Flow](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/BootArchitecture/JetsonThorBootFlow.html)
- [Board Automation](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/BoardAutomation.html)
- [Tegra Combined UART](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools/TegraCombinedUART.html)
- [Controller Area Network (CAN)](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/ControllerAreaNetworkCan.html)
- [Jetson Thor Adaptation and Bring-Up](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/JetsonThorAdaptationBringUp.html)
- [Camera Development](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment.html)
- [Camera Support Matrix](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/CameraDevelopmentSupportMatrix.html)
- [Camera Software Development Solution for Jetson Thor](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/CameraSoftwareDevelopmentSolutionThor.html)
- [Holoscan Sensor Bridge (HSB)](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/Holoscan-Sensor-Bridge.html)
- [GMSL Camera Development Guide](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSLCameraDevelopment.html)
- [SIPL Query JSON Guide](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-JSON-Query-Guide.html)
- [Using HSL in UDDF](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/hsl_toolchain.html)
- [Flashing Support for Jetson Thor](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/FlashingSupportJetsonThor.html)
- [nv-load-display-modules Service](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/NvLoadDisplayModulesService.html)
- [Display Configuration for Jetson Thor](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/ThorDisplayconfig.html)
- [Enable 25 Gigabit Ethernet on QSFP Port](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/Enable25GbEthernetOnQSFP.html)
- [PWM Frequency Configuration](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/IoCustomization/pwm.html)
- [Accelerated Decode with FFmpeg](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia/AcceleratedDecodeWithFfmpg.html)
- [Jetson Thor Product Family](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonThor.html)
- [Disk Encryption](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption.html)
- [Factory Secure Key and Expansion Key Provisioning](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FSKP.html)
- [Firmware TPM](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [fTPM Boot Flow](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/BootFlow.html)
- [Security Keys List](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/KeyList.html)
- [Memory Encryption](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/MemoryEncryption.html)
- [OP-TEE: Open Portable Trusted Execution Environment](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee.html)
- [PVA Authentication](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/PVAAuthentication.html)
- [Rollback Protection](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/RollbackProtection.html)
- [Secure Boot](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot.html)
- [PKC Key Revocation](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/PkcKeyRevocation.html)
- [Quick Start Guide to Enable Secure Boot for Jetson Thor](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/QuickStartThor.html)
- [UEFI Payload Encryption](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/UefiPayloadEncryption.html)
- [Secure Storage](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureStorage.html)
- [Jetson Thor Series](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SO/JetsonThorSeries.html)
- [Welcome](https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/index.html)

## Landing pages (3)

### Jetson Thor (product page)

- **URL:** https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-thor/
- **Summary:** Marketing/product hub for NVIDIA Jetson Thor (Blackwell) — high-end physical AI / robotics edge computer. Specs, developer kit positioning vs Orin, links into JetPack and related Isaac/IGX software.
- **Sections:** Get Yours Today; A Compact Powerhouse for Agentic AI and Robotics; NVIDIA Jetson Thor Unlocks Real-Time Reasoning for Physical AI; Maximizing Memory Efficiency to Run Bigger Models on NVIDIA Jetson; Industry-Leading Performance for Humanoid Robots; AI Performance; Memory Bandwidth; CPU

### NVIDIA JetPack SDK

- **URL:** https://developer.nvidia.com/embedded/jetpack
- **Summary:** Official JetPack software stack for Jetson (JetPack 7 for Orin + Thor): CUDA/cuDNN/TensorRT AI compute, PyTorch/vLLM/Triton, Jetson Linux, flashing, security/OTA, multimedia/CV libs, Holoscan/Isaac/DeepStream. Notes Thor uses SBSA stack — use SBSA installers. Entry for downloads, NemoClaw, Jetson agent skills.
- **Sections:** JetPack 7 Overview; Agentic Frameworks on JetPack SDK; Components of the JetPack SDK; AI Compute Stack; AI Frameworks; Jetson Linux Components and Libraries; Other JetPack Components; Supported SDKs

### Jetson Linux Developer Guide (r39.2 GA)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/
- **Summary:** Primary software developer guide for Jetson Linux 39.2 GA covering Jetson Thor and Orin families: flashing, bootloader, kernel, multimedia, camera (Argus/SIPL), security, power, adaptation/bring-up. Use TOC URLs below for deep pages; fetch live page for full procedures.
- **Sections:** Jetson Developer Kits and Modules #; Software for Jetson Modules and Developer Kits #; Documentation for Jetson Modules and Developer Kits #; Devices Supported by This Document #; How Developer Guide Topics Identify Devices #

## Introduction (1)

### Quick Start

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/IN/QuickStart.html
- **Summary:** This topic will help you get started quickly using NVIDIA ® Jetson™ Linux with an NVIDIA Jetson developer kit. Both Jetson modules and Jetson developer kits are available from NVIDIA. A Jetson developer kit includes a non-production-specification Jetson module attached to a reference carrier board. You can use it with NVIDIA ® JetPack ™ SDK to develop and test software for your use case. Jetson developer kits are not intended for production use.
- **Sections:** Types and Models of Jetson Devices #; Preparing a Jetson Developer Kit for Use #; Assumptions #; Environment Variables #; To Flash the Jetson Developer Kit Operating Software #; Jetson Modules and Configurations #; To Determine Whether the Developer Kit Is in Force Recovery Mode #

## Architecture (6)

### Boot Architecture

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/BootArchitecture.html
- **Summary:** This section describes NVIDIA ® Jetson™ boot architecture.

### Jetson AGX Orin, Orin NX, and Orin Nano Boot Flow

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/BootArchitecture/JetsonOrinSeriesBootFlow.html
- **Summary:** Boot flow is the sequence of operations that the Bootloader performs to initialize the SoC and boot NVIDIA ® Jetson™ Linux. The Bootloader performs the following major operations: Initialize the storage devices, memory controller (MC), external memory controller (EMC), and CPU.
- **Sections:** BootROM #; PSCROM #; MB1 #; MB2 #; MB2 Applet #; UEFI #; Cold Boot Sequence #

### Jetson Thor Boot Flow

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/BootArchitecture/JetsonThorBootFlow.html
- **Summary:** Boot flow is the sequence of operations that the Bootloader performs to initialize the SoC and boot NVIDIA ® Jetson™ Linux. The Bootloader performs the following major operations: Initialize the storage devices, memory controller (MC), external memory controller (EMC), and CPU.
- **Sections:** PSCROM #; HPSEROM #; SBROM #; UEFI #

### Partition Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/BootArchitecture/PartitionConfiguration.html
- **Summary:** NVIDIA ® Jetson™ Linux supports formatting mass storage media into multiple partitions for storing data, such as the device OS image, bootloader image, device firmware, and bootloader splash screen. Some Jetson platforms have similar characteristics, such as identical partition configurations. This topic groups these platforms and provides information about each group. The supported platforms are grouped in the following way:
- **Sections:** How Jetson Partition Configurations Are Described #; Partition Configuration Files #; Format of a Partition Configuration File #; <partition_layout> Element #; <device> Element #; <partition> Element #; <partition> Child Elements #; List of Translated Keywords #

### Jetson Software Architecture

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/JetsonSoftwareArchitecture.html
- **Summary:** NVIDIA Jetson software is the most advanced AI software stack yet, purpose-built for the next era of edge computing, where physical AI, generative models, and real-time intelligence converge. At the highest level, Jetson software is optimized for humanoid robotics and machines that interact dynamically with the physical world. It is fully ready for generative AI, enabling developers to deploy large language models (LLM), diffusion models, and…
- **Sections:** Documentation #; AI Components #; AI Frameworks #; Jetson Linux Components and Libraries #; Other JetPack Components #; Supported SDKs #; Community Support #

### Yocto on Jetson Platforms

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AR/YoctoOnJetson.html
- **Summary:** Beginning with JetPack 7.2, NVIDIA supports Yocto on Jetson platforms. This support provides a path to build custom, reproducible Linux images for Jetson while continuing to use Jetson Linux and JetPack components. The work is aligned with the OpenEmbedded for Tegra (OE4T) project, and NVIDIA is contributing back to that community. The Yocto Project is an open source build framework for creating custom Linux-based systems. Yocto is not a…
- **Sections:** What Is Yocto? #; Basic Yocto Concepts #; Why Use Yocto on Jetson? #; Jetson Yocto Model #; What NVIDIA Provides #; Typical Development Flow #; Where to Go Next #

## Software feature overview (2)

### Jetson Orin Series

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SO/JetsonOrinSeries.html
- **Summary:** NVIDIA ® Jetson™ Linux supports these software features, which provide users a complete package to bring up Linux on Jetson AGX Orin™ , Jetson Orin™ NX , and Jetson Orin™ Nano devices. We recommend using a camera with a frame rate of less than or equal to 60 FPS.
- **Sections:** Bootloader #; Toolchain #; Kernel #; Camera Interface #; LSIO #; HSIO #; HDMI #; DisplayPort #

### Jetson Thor Series

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SO/JetsonThorSeries.html
- **Summary:** NVIDIA ® Jetson™ Linux supports these software features, which provide users a complete package to bring up Linux on Jetson Thor devices. SIPL (Safe Image Processing Library) [With HW ISP & MGBe]
- **Sections:** Bootloader #; Toolchain #; Kernel #; Camera Interface #; LSIO #; HSIO #; HDMI #; DisplayPort #

## Software features in depth

### Flashing & rootfs

#### Flashing Support

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/FlashingSupport.html
- **Summary:** Use flash.sh to flash a Jetson device with Bootloader and the kernel, and optionally, flash the root file system to an internal or external storage device. Use l4t_initrd_flash.sh to flash internal or external media connected to a Jetson device. This script uses the recovery initial ramdisk to do the flashing, and can flash internal and external media using the same procedure. Because this script uses the kernel for flashing, it is generally…
- **Sections:** Before You Begin #; Basic Flashing Script Usage #; Basic Flashing Procedures #; Installing the Flash Requirements #; Flashing the Target Device #; Flashing by Using a Convenient Script #; Flashing the Target Device to Mount a rootfs Specified by a UUID #; Flashing the Target Device to Mount a rootfs Specified by the Partition Device Name #

#### Flashing Support for Jetson Thor

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/FlashingSupportJetsonThor.html
- **Summary:** Use l4t_initrd_flash.sh to flash a Jetson device. You can flash with initrd (initial RAM disk) to both internal media and external media connected to a Jetson device. The procedure uses initrd and USB device mode. Tools and instructions for flashing with initrd can be found in the directory /Linux_for_Tegra/‌tools/‌kernel_flash/ . For more detailed information, see README_initrd_flash.txt in the same directory.
- **Sections:** Before You Begin #; Basic Flashing Script Usage #; Basic Flashing Procedures #; Installing the Flash Requirements #; Flashing the Target Device #; Flashing by Using a Convenient Script #; Explaining Board Configuration File and Generating a Flash Image to Flash Later #; Backing Up and Restoring a Jetson Device #

#### Root File System

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/RootFileSystem.html
- **Summary:** NVIDIA Jetson Linux Driver Package (L4T) comes with a pre-built sample root file system created for the NVIDIA Jetson developer kits. This chapter describes: NVIDIA provides a tool to generate a root file system. To use the tool, navigate to the tools/samplefs directory in the extracted NVIDIA driver package:
- **Sections:** Manually Generate a Root File System #; Desktop Flavor Root File System #; Minimal Flavor Root File System #; Basic Flavor Root File System #; Execute the Script on a Non-Ubuntu 24.04 Host #; Using the Script #; Root File System Redundancy #; Rootfs Selection #

### Bootloader

#### Bootloader

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader.html
- **Summary:** This topic discusses features supported in the Bootloader, the component of NVIDIA ® Jetson™ Linux that boots the operating system when the device is powered up or reset.

#### BootROM Reset PMIC Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/BootROMResetPMICConfig.html
- **Summary:** For some T23x platforms, BootROM might be required to bring PMIC rails to OTP values in the L1 and L2 reset boot paths. This process is completed by issuing I2C commands, which are encoded in AO scratch registers by MB1, and are based on the BootROM reset configuration in MB1 BCT. The reset cases where the BootROM issues these commands includes the following:
- **Sections:** Specifying AO Blocks #

#### Common Prod Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/CommonProdConfig.html
- **Summary:** The prod configurations are the system-characterized values of interface and controller settings, which are required for the interface to work reliably for a platform. The prod configurations are set separately at the controller and pinmux/pad levels. This file contains the common pinmux/pad level prod settings. addr-value-data : List of <Absolute PADCTL register address, mask, data>

#### Controller Product Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/ControllerProdConfig.html
- **Summary:** The prod configurations are the system-characterized values of the interface and controller settings, which allow an interface to work reliably for a platform. The prod configurations are set separately at the controller and pinmux/pad levels. This file contains the controller-level prod settings. The DTS configuration file is in the following format:

#### DRAM-ECC

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/DramEcc.html
- **Summary:** Error correction code (ECC) protection provides a means to detect and correct errors within DRAM. Enabling DRAM-ECC ensures that for every 32 bytes of data, 2 bytes are allocated for ECC. This mechanism works by calculating and writing 2 ECC bytes alongside each data byte write. Similarly, during data reads, the 2 ECC bytes are read to verify data integrity, ensuring the stored ECC matches the calculated ECC. Any discrepancies are flagged by…
- **Sections:** Components #; Hardware #; Software #; Stages #; Verification Steps #; Common Steps #; Single Bit Error (SBE) Testing #; Double Bit Error (DBE) Testing #

#### GPIO Interrupt Mapping Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/GpioInterruptMapConfig.html
- **Summary:** To reduce the interrupt hunt time for GPIO pins from an ISR, in T23x, each GPO controller has eight interrupt lines to LIC. This provides the opportunity to map the GPIO pin to any of these interrupts. The configuration is specified in the GPIO interrupt configuration file. Each entry in the configuration file is in the following form:

#### MB2 BCT Misc Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/Mb2BctMiscConfig.html
- **Summary:** This section provides additional information about the MB2 BCT Misc configuration file. The following table lists the Boolean flags that enable or disable functionality in MB2:
- **Sections:** MB2 Feature Fields #; MB2 Firmware Data #

#### Miscellaneous Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/MiscConfig.html
- **Summary:** The different settings that do not fit into the other categories are documented in miscellaneous configuration file. These features are Boolean flags that enable or disable functionality in MB1:
- **Sections:** MB1 Feature Fields #; PSC-BL Synchronization Features #; Multi-SKU Support Configuration #; Clock Data #; Clock Feature Control #; Clock Dividers #; NAFLL Configuration #; CPU Clock Configuration #

#### OEM-FW Ratchet Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/OemFwRachetConfig.html
- **Summary:** Roll-back prevention for oem-fw is controlled by using the OEM-FW Ratchet configuration. Ratcheting is when the older version of the software is precluded from loading. The ratchet version of the software is incremented after fixing the security bugs, and this version is compared against the version that is stored in the Boot Component Header (BCH) of the software before loading. This file defines the minimum ratchet level for OEM-FW…

#### Pad Voltage DT Binding

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/PadVoltageDtBinding.html
- **Summary:** Tegra pins and pads are designed to support multiple voltage levels at a given interface. They can operate at 1.2 volts (V), 1.8 V or 3.3 V. Based on the interface and power tree of a given platform, the software must write to the correct voltage of these pads to enable interface. If pad voltage is higher than the I/O power rail, then the pin does not work on that level. If pad voltage is lower than the I/O power rail, then it can damage the…

#### Pinmux and GPIO Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/PinmuxGpioConfig.html
- **Summary:** The pinmux configuration file provides pinmux and GPIO configuration, which is generated by using the pinmux spreadsheet. The pinmux DTS file is in the Linux_for_Tegra/bootloader/generic/BCT directory.

#### Platform Configuration Profile

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/PlatformConfigurationProfile.html
- **Summary:** The Platform Configuration Profile (PCP) provides a way to enable or disable features defined in the Boot Configuration Table (BCT). It is supported beginning with the T264 device. It allows for flexible configuration of boot features across various boot chains and scenarios. Defined as BCT_FLAGS_FILE in the common board config file (such as t264.conf.common ).
- **Sections:** Purpose #; Types of PCP #; Common PCP #; Overlay PCP #; Common PCP Example #; Overlay PCP Example #

#### PMIC Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/PmicConfig.html
- **Summary:** During the system boot, MB1 enables system power rails for CPU, CORE, and DRAM and completes some system PMIC configurations. The typical configurations are: Enabling and setting of voltages of rails might require the following platform-specific configurations:
- **Sections:** Common Configuration #; Rail-Specific Configuration #

#### SDRAM Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/SdramConfig.html
- **Summary:** Here is the DTS format for the SDRAM configuration: /{ sdram { mem_cfg_<N>: mem-cfg@<N> { <parameter> = <value>; }; }; }; &mem_cfg_<N> { #include "\<mem_override_dts\>" }; where
- **Sections:** Carveouts #; GSC Carveouts #; Non-GSC Carveouts #

#### Security Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/SecurityConfig.html
- **Summary:** MB1 and MB2 program most of the SCRs and firewalls in T264. The list of SCRs and firewalls, their order, and their addresses are predetermined. The values are taken from the SCR configuration file. Each entry in this configuration file is in the following form:

#### Storage Device Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/StorageDeviceConfig.html
- **Summary:** The Storage Device configuration file contains the platform-specific settings for storage devices in the MB1/MB2 stages. The DTS configuration file is in the following form:
- **Sections:** QSPI Flash Parameters #; SDMMC Parameters #; UFS Parameters #

#### T23x/T26x Boot Configuration Table

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/T23xBCTLoaderIntro.html
- **Summary:** The Boot Configuration Table (BCT) is a set of platform-specific configuration data that is consumed by a boot component. BootROM and MB1 consume BCT in binary form, which is generated by using the parsing device tree source configuration files, with a .dts file extension, by tegrabct_v2 . Starting from T23x, the config file format changed from legacy <parameter> = <value>; to Device Tree Source (DTS) format for the following reasons:
- **Sections:** BR-BCT #; MB1-BCT #; Mem-BCT #; MB2-BCT #

#### UEFI Adaptation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/UEFI.html
- **Summary:** This section provides high level info for the users to adapt to using UEFI. UEFI sources and compilation details for this release are available NVIDIA/edk2-nvidia .
- **Sections:** Sources and Compilation #; Viewing the BSP Version in UEFI #; UEFI Variables #; Boot Order Selection #; Supported Boot Device and the Default Boot Order #; Selecting the Boot Device in the UEFI #; Customizing the Default Boot Order in the Configuration File #; Overriding the Default Boot Order During Flashing #

#### Update and Redundancy

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/UpdateAndRedundancy.html
- **Summary:** NVIDIA ® Jetson™ Linux supports Bootloader update and redundancy on all Jetson platforms. The Bootloader update process performs a safe Bootloader update and ensures that a workable Bootloader partition remains available during an update. It accomplishes this using A/B update , a feature that maintains two sets of Bootloader partitions, Slot A and Slot B , each of which is a complete set of the partitions that contain boot images.
- **Sections:** A/B Slot Layout #; A/B System Update #; Partition Selection #; Bootloader Implementation #; Jetson Orin Implementation #; Jetson Thor Implementation #; Bootloader Scratch Register #; Partition Settings #

#### UPHY Lane Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Bootloader/UphyLaneConfig.html
- **Summary:** UPHY lanes can be configured to be owned by various IPs such as XUSB, NVME, MPHY, PCIE, NVLINK, and so on. MB1 supports NVME and UFS as boot devices for the UPHY lanes that need to be configured to access the storage in MB1 and MB2. This configuration file defines the UPHY lane configurations that are needed for MB1. In T23x, BPMP-FW is loaded by MB1 and MB2 relies on BPMP-FW for UPHY configuration.

### Kernel & I/O

#### Kernel

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel.html
- **Summary:** This topic discusses aspects of the NVIDIA ® Jetson™ Linux kernel.

#### BMI088 IMU Driver

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/Bmi088ImuIioDriver.html
- **Summary:** The Linux industrial IO (IIO) is framework used to implement sensor drivers such as ADC (analog to digital converters), temperature, light, IMU (inertial measurement unit). The BMI088 is Bosch IMU which encompasses accelerometer, gyroscope and temperature. This I2C based driver implements accelerometer and gyroscope part of the IMU. The BMI088 driver is enabled by default in the kernel config. It registers the accelerometer and gyroscope with…
- **Sections:** BMI088 Driver #; Device Tree #; Required Properties #; Optional Properties #; Accelerometer IIO Attributes #; Gyroscope IIO Attributes #; Testing BMI088 Driver #; Hardware Timestampping Engine (HTE) #

#### Bring Your Own Kernel

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/BringYourOwnKernel.html
- **Summary:** To facilitate support by commercial Linux distributions, for several years, NVIDIA has contributed substantial portions of its kernel support directly to the upstream kernel, and this effort continues. Commercial Linux options are becoming available as a result of this work. NVIDIA is working to upstream the necessary changes to the kernel source that are required for Jetson products. However, time constraints sometimes result in a patch…
- **Sections:** Introduction #; Process Overview to Bring Your Own Kernel #; Upstream Patches #

#### Kernel Debugging Tools

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DebuggingTools.html
- **Summary:** NVIDIA ® Jetson™ Linux lets you generate a kernel crash dump , which is a portion of the system’s volatile memory (RAM) saved to disk when the execution of the kernel is disrupted. The following events can cause such a disruption: You can find more details about kernel crash dumps at https://ubuntu.com/server/docs/kernel-crash-dump .
- **Sections:** How to Setup #; Testing/Validation #

#### Display Configuration and Bring-Up

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp.html
- **Summary:** NVIDIA ® Jetson™ Board Support Package (BSP) supports a variety of modes on HDMI ® and DP monitors, including the CEA modes and detailed timing modes from the display EDID.

#### Common Display Configurations for All Platforms

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/CommonDisplayconfig.html
- **Summary:** This page applies to all Jetson platforms. For platform-specific information, refer to the following pages: The screen resolution can be modified using the xrandr utility or RandR protocol .
- **Sections:** Set HDMI or DP Screen Resolution #; Virtual Terminal Switching Support #; Seamless Display Support #

#### nv-load-display-modules Service

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/NvLoadDisplayModulesService.html
- **Summary:** Two different sets of display drivers are used across Jetson modules. Jetson Orin devices use the NVGPU driver, nvgpu.ko , for graphics and compute and the following drivers for display: Jetson Thor devices have a combined graphics, compute, and display driver in nvidia.ko . The corresponding drivers for Jetson Thor and later devices are as follows:
- **Sections:** Implementation #; Checking the Service State #

#### Display Configuration for Jetson Orin

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/OrinDisplayconfig.html
- **Summary:** Display Control Block (DCB) describes the display outputs and their configurations on a platform. Refer to https://download.nvidia.com/open-gpu-doc/DCB/2/DCB-4.x-Specification.html for more information about DCB. The DCB blob is stored in platform specific dtsi files in the nvidia,dcb-image property under the display node. The Jetson AGX Orin DCB blob is in the tegra234-dcb-p3701-0000-a02-p3737-0000-a01.dtsi file.
- **Sections:** Update DCB Blob for Custom Carrier Boards #; dcb_tool #; Changing the Display Function Between DP and HDMI #; Known Limitations #

#### Display Configuration for Jetson Thor

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/DisplayConfigurationAndBringUp/ThorDisplayconfig.html
- **Summary:** A display control block (DCB) describes the display outputs and their configurations on a platform. For information about DCB, refer to Device Control Block 4.x Specification . The DCB blob is stored in platform-specific DTSI files in the nvidia,dcb-image property under the display node. The Jetson Thor DCB blob is in the tegra264-p4071-0080-p3834-0008-dcb.dtsi file.
- **Sections:** Update DCB Blob for Custom Carrier Boards #; dcb_tool #; Modifying DCE DTB #

#### Enable 25 Gigabit Ethernet on QSFP Port

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/Enable25GbEthernetOnQSFP.html
- **Summary:** In the Jetson AGX Thor Developer Kit, the QSFP port can support both 10 Gigabit Ethernet (10GbE) and 25 Gigabit Ethernet (25GbE). The default is 10GbE. The QSFP port can support only one configuration at a time. To enable 25GbE, edit the flashing configuration file jetson-agx-thor-devkit.conf and set ODMDATA as follows:
- **Sections:** How to Optimize the Performance of 25GbE #; Optimizing Performance of 25 Gigabit Ethernet on QSFP Port #; Verifying 4×25 Gbps Aggregate Throughput on the QSFP Port #; UDP (4×25Gbps, 9K MTU) #; TCP (4×25 Gbps, 9K MTU) #

#### Generic Timestamp Engine

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/GenericTimestampEngine.html
- **Summary:** Applies to : Jetson AGX Orin, Orin NX and Orin Nano series Starting from JP 6.0, the Generic Timestamp Engine (GTE) driver has been marked as deprecated and replaced by the Hardware Timestamp Engine (HTE) from the upstream kernel.
- **Sections:** Enabling the HTE Driver #

#### I/O Customization

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/IoCustomization.html
- **Summary:** This section describes how to customize on-SoC I/O controllers on NVIDIA ® Jetson™ platforms by modifying the kernel device tree.

#### PWM Frequency Configuration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/IoCustomization/pwm.html
- **Summary:** Applies to Jetson Orin Nano, Jetson Orin NX, Jetson AGX Orin (Tegra234), and Jetson AGX Thor (Tegra264). This topic describes how to choose a pulse width modulation (PWM) output frequency on NVIDIA ® Jetson™ platforms with the on-SoC PWM controllers exposed by the pwm-tegra driver ( drivers/pwm/pwm-tegra.c ), and how to express that choice in the kernel device tree (DTS).
- **Sections:** How PWM Output Frequency Is Generated #; Knobs Available to the Developer #; Source Clock Parent #; nvidia,pwm-depth Property #; PWM Period #; Reference Table: Reachable Period Range (Tegra234) #; Reference Table: Reachable Period Range (Tegra264) #; Example: Configure Tegra234 PWM5 With CLK_32K As Parent For 1 Hz Output #

#### Kernel Boot Time Optimization

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/KernelBootTimeOptimization.html
- **Summary:** NVIDIA ® Jetson™ Linux provides a generic boot kernel for with which you can develop your product. To decrease kernel boot time, customize the provided kernel based on the requirements of your product. The kernel includes a default configuration that enables all supported hardware features and searches all available devices for boot scripts. This provides out-of-the box support for the widest possible variety of controllers, features, storage…
- **Sections:** Device Tree Nodes #; Environment Configuration #; Disable Console Printing over UART #; Compile-Time Configuration #; Asynchronous Probe #; To move the driver to another thread #; To reduce file system initialization time #; To modularize the kernel drivers #

#### Kernel Customization

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/KernelCustomization.html
- **Summary:** You can manually rebuild the kernel used for the NVIDIA ® Jetson™ Linux. You must have Internet access for this. You have installed Git. You can install with the following command:
- **Sections:** Prerequisites #; Obtaining the Kernel Sources #; To Sync the Kernel Sources with Git #; To Manually Download and Expand the Kernel Sources #; Building the Jetson Linux Kernel #; Building the NVIDIA Out-of-Tree Modules #; Building the DTBs #; Signing and Encrypting the Kernel, the kernel-dtb, and the initrd Binary Files #

#### Installing Real-Time Kernel

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/RealTimeKernel.html
- **Summary:** Real-Time Kernel support is provided with Developer-Preview quality for the following platforms: You can install Real-Time Kernel by using OTA update or building the kernel sources manually.
- **Sections:** Real-Time Kernel Using OTA Update #; Installing the Real-Time Kernel Packages on a Jetson Device #; Removing the Real-Time Kernel Packages from a Jetson Device #; Switch to a Different Kernel #; Building Real-Time Linux Kernel Sources #; Real-Time Kernel Latency Results on Jetson Thor #; Kernel Tuning Steps #; System Setup and Load During Latency Measurement #

### Multimedia & graphics

#### Graphics

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics.html
- **Summary:** This section provides an overview of the graphics support for this release. This section is divided into the following subsections:

#### EGLDevice

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/Egldevice.html
- **Summary:** This topic describes EGL ™ mechanisms that you can use to render 3D images on a pure EGL display. Such a display does not use a window system. EGLDevice provides a mechanism to access graphics functionality in the absence of or without reference to a native window system. It is a method to initialize EGL displays and surfaces directly on top of GPUs/devices rather than native window system objects. It is a cross-platform method to discover…
- **Sections:** EGLDevice #; EGLOutput #; EGLStream #; Extensions #; Rendering to EGLDevice #; Creating a EGLStream Producer Surface #; Rendering to an EGLDevice Through the EGLStream #; Setting Up the Display with DRM #

#### EGLStream

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/Eglstream.html
- **Summary:** EGLStream is a mechanism that efficiently transfers a sequence of image frames from one API to another, e.g., from OpenGL ® to NVIDIA ® CUDA ® . In EGLStream architecture a producer and a consumer are attached to each end of a stream object. A producer adds image frames to the stream. A consumer retrieves image frames from the stream.
- **Sections:** EGLStream Producers #; EGLStream Consumers #; EGLStream Operation Modes #; Mailbox Mode #; FIFO Mode #; EGLStream Pipeline #; To build a simple EGLStream pipeline #; To destroy the EGLStream pipeline #

#### Graphics APIs

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/GraphicsAPIs.html
- **Summary:** Extensions supported for getting these components to work † Refer to NVIDIA/libglvnd for more information about GLVnd.
- **Sections:** EGL Details #; Supported EGL Extensions #; GL and Vulkan Details #; Supported OpenGL Extensions #; Supported OpenGL-ES Extensions #; Supported GLX Extensions #

#### Graphics Programming

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/GraphicsProgramming.html
- **Summary:** Use the information in this topic to understand graphics programming for this release. This information includes topics such as binary shader program management, the shader program compiler, and OpenGL ES Programming tips. Binary Shader Program Management discusses how shader programs are stored, compiled, and cached.

#### Binary Shader Program Management

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/GraphicsProgramming/BinaryShaderProgramManagement.html
- **Summary:** Shader programs are ordinarily stored in source form, and are compiled and linked by the OpenGL ® ES driver when the application first uses them by making OpenGL ES API calls. You can also precompile shader programs with glslc, an offline shader compiler. This eliminates the need to compile those shader programs at run time. If all of the shader programs an application uses are precompiled, the OpenGL ES driver can save additional time and…
- **Sections:** Automatic Shader Cache #; To make a cache read-only #; Comparison and Combination #

#### GLSLC Shader Program Compiler

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/GraphicsProgramming/GlslcShaderProgramCompiler.html
- **Summary:** This topic describes glslc , which is a compiler for OpenGL ® ES 3.x program binaries. This compiler runs on the Linux host system to produce program binaries that can be transferred to the target NVIDIA ® Jetson™ device. glslc produces program binaries for a particular OpenGL ES driver. Compiled shaders and other programs must be recompiled whenever a new driver is installed.
- **Sections:** To compile a shader program #; Compiled Shader Program Characteristics #; Libraries Loaded on Demand #

#### OpenGL ES Programming Tips

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/GraphicsProgramming/OpenglEsProgrammingTips.html
- **Summary:** This topic is for readers who have some experience programming OpenGL ® ES and want to improve the performance of their OpenGL ES application. It aims at providing recommendations on getting the most out of the API and hardware resources without diving into too many architectural details. Some of the recommendations in this topic are incompatible with each other. One must consider the trade-offs between CPU load, memory, bandwidth, shader…
- **Sections:** Programming Efficiently #; State #; Geometry #; Shader Programs #; Textures #; Miscellaneous #; Optimizing OpenGL ES Applications #; Avoiding Memory Fragmentation #

#### OpenWFD

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/OpenWFD.html
- **Summary:** This topic describes the Khronos ™ Open Windowing Foundation - Display ™ (OpenWFD) API that can be used to interact with the display hardware. OpenWFD does not require the presence of a native windowing system. OpenWFD is a Khronos API that provides a low-level hardware abstraction interface for windowing systems, and applications can interact directly with the display by using the OpenWFD API. The specification of the OpenWFD API is…
- **Sections:** Supported OpenWFD APIs #; Supported OpenWFD Extensions #; WFD_NVX_create_source_from_nvscibuf #; WFD_NVX_commit_non_blocking #; WFD_NVX_nvscisync #; WFD_NVX_port_mode_timings #; OpenWFD Usage Guidelines #

#### Sample Applications

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/SampleApplications.html
- **Summary:** This topic contains information about several sample applications that are provided with NVIDIA ® Jetson™ Linux. NVIDIA graphics samples are included in Jetson Linux. This topic gives detailed steps for building and running these samples on the target.
- **Sections:** NVIDIA Graphics Sample Applications #; Building the Samples #; Starting the Graphics System #; To launch Weston with a script #; To launch Weston manually #; Upstream Sample Application: Gears #

#### Vulkan SC

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/VulkanSC.html
- **Summary:** Vulkan SC is a streamlined, deterministic, robust API based on Vulkan 1.2 that enables state-of-the-art GPU-accelerated graphics and computation to be deployed in safety-critical systems that are certified to meet industry functional safety standards. Jetson Linux supports the Vulkan SC 1.0 specification. For the latest Vulkan SC 1.0 specification with extensions, refer to Vulkan SC Specification .
- **Sections:** Vulkan SC Extensions #; Instance Extensions #; Device Extensions #; Window System #; Vulkan SC Loader #; Vulkan SC Validation Layer #; Vulkan SC Pipeline Cache Compiler (PCC) Tool #; Vulkan SC Packages #

#### Vulkan SC Samples

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Graphics/VulkanSCSamples.html
- **Summary:** Vulkan SC samples are included in Jetson Linux. This topic provides detailed steps to build and run these samples on the target. tar xf public_sources.tbz2 -C ./ cd ./Linux_for_Tegra/source mkdir nvsci_headers tar xf nvsci_headers.tbz2 -C ./nvsci_headers Copy all the headers files under nvsci_headers to /usr/include on target.
- **Sections:** Building the Samples #; Prerequisites #; Build on the Target #; Running Vulkan SC Samples #; Running the vulkanscinfo Command #; Running the vksc_01tri Sample #; Running the vksc_computeparticles Sample #

#### Hardware Acceleration in the WebRTC Framework

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/HardwareAccelerationInTheWebrtcFramework.html
- **Summary:** WebRTC is a free open source project that provides real-time communication capabilities to browsers and mobile apps. A major feature of WebRTC is the ability to send and receive interactive HD videos. Fast processing of such videos requires hardware accelerated video encoding.
- **Sections:** Typical Buffer Flow for NvEncoder #; Typical Buffer Flow for NvDecoder #; Typical WebRTC Architecture of NvPassThroughEncoder #; Typical WebRTC Architecture of NvPassThroughDecoder #; Application and Unit Test Setup #; To set up and test the NvEncoder sample application #; Important Method Calls for NvEncoder #; To create a hardware-enabled video encoder #

#### Multimedia

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia.html
- **Summary:** NVIDIA ® Jetson™ Linux includes the below multimedia features. The nvbuf_utils to NvUtils Migration Guide can be found on https://developer.nvidia.com/embedded/jetson-linux-r351 .

#### Accelerated Decode with FFmpeg

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia/AcceleratedDecodeWithFfmpg.html
- **Summary:** The NVIDIA ffmpeg package supports hardware-accelerated decoding on NVIDIA ® Jetson™ devices. On the Jetson Thor platform, FFmpeg supports hardware-accelerated decoding, encoding, and transcoding using both nvbufsurface and cuda hardware acceleration interfaces. Hardware-accelerated video transformation operations using VIC are supported with the nvbufsurface interface. GPU-based transformation operations are supported with both nvbufsurface…
- **Sections:** Install ffmpeg Binary Package in Jetson Linux Builds #; Get Source Files for the ffmpeg Package #; Prerequisite for the Jetson Thor Platform #; Decoding on the Jetson Thor Platform #; Encoding on the Jetson Thor Platform #; Transcoding on the Jetson Thor Platform #; Decoding and Transforming on the Jetson Thor Platform #; JPEG Transcoding on the Jetson Thor Platform #

#### Accelerated GStreamer

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia/AcceleratedGstreamer.html
- **Summary:** This topic is a guide to the GStreamer-1.0 version 1.20 based accelerated solution included in NVIDIA ® Jetson™ Ubuntu 22.04. This section explains how to install and configure GStreamer.
- **Sections:** GStreamer-1.0 Installation and Set up #; Installing GStreamer-1.0 #; Checking the GStreamer-1.0 Version #; Installing Accelerated GStreamer plugins #; GStreamer-1.0 Plugin Reference #; Prerequisites for JPEG Encode/Decode on Jetson Thor Platform #; Decode Examples #; Audio Decode Examples Using gst-launch-1.0 #

#### Multimedia APIs

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia/MultimediaApis.html
- **Summary:** The Multimedia API is a collection of low-level APIs that support flexible application development. These low-level APIs enable flexibility by providing better control over the underlying hardware blocks. V4L2 API for encoding, decoding, and other media functions.
- **Sections:** Multimedia Demo Applications #; nvgstplayer-1.0 #; nvgstcapture-1.0 #

#### Software Encode in Orin Nano

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Multimedia/SoftwareEncodeInOrinNano.html
- **Summary:** The NVIDIA® Jetson™ Orin Nano does not have the NVENC engine. This application note provides information about how to migrate to software encoding using the libav (FFmpeg) encoders, and the section on the GStreamer pipelines provides details on how to use the software encoding as part of the NVIDIA-accelerated gstreamer pipelines. This document shows only the encoding of H.264 codec format. This section will demonstrate the encoding of H264…
- **Sections:** Argus Camera Software Encode Sample #; Building and Running #; Supported Options #; Flow #; Key Structure and Functions #; Hardware-to-Software Encoder Properties Mapping #; NvBufSurfaceCopy Output #; Performance and Quality Comparison Numbers #

#### Windowing Systems

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/WindowingSystems.html
- **Summary:** This topic describes windowing systems supported in NVIDIA ® Jetson™ Linux: Weston (Wayland) , a server communication protocol, more recent than Gnome, that is designed as a replacement for X Window System

#### Weston (Wayland)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/WindowingSystems/WestonWayland.html
- **Summary:** Wayland is a protocol for communication between a display server and its clients. A Wayland server uses the Wayland protocol to communicate with a GUI program, which is a Wayland client . A Wayland server is also called a Wayland compositor , as it also acts as a compositing window manager. The Weston server, usually just called Weston , is the reference implementation of a Wayland compositor. It manages the displays, including composition of…
- **Sections:** Weston/Wayland Architecture #; Shells #; Configuration #; Environment Variables #; GBM #; Custom Upgrades by NVIDIA #; Enhanced Downscaling Quality with GL Renderer #; Socket Naming Adjustment #

#### X Window System

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/WindowingSystems/XWindowSystem.html
- **Summary:** X Window System provides windowing, graphic display, and device management services to graphic user interface (GUI) applications that run under Linux. X server is the standard implementation of X Window System, and is supported in Jetson Linux. The official X Window System documentation is available on the X.Org Foundation’s X.Org documentation page.
- **Sections:** Starting X Server Manually #; To start X server #; To stop X server #; Runtime Configuration #; Using xrandr for Runtime Configuration #; Querying Supported Displays and Screen Resolutions #; To query attached displays and detect available modes #; Obtaining Additional Help #

### Camera

#### Camera Development

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment.html
- **Summary:** This section describes the camera software solution included in NVIDIA ® Jetson™ Linux. NVIDIA Jetson offers SIPL as the major camera software path, while maintaining support for Argus (with no new feature additions). SIPL is the primary camera software beginning with Jetson Thor. The following table summarizes how Argus and SIPL differ in scope, architecture, and direction.

#### Argus Framework

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/ArgusFramework.html
- **Summary:** This section describes the NVIDIA ® Jetson™ camera software stack built on libargus and the CSI/GMSL capture path on supported platforms.

#### Argus NvRaw Tool

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/ArgusNvrawTool.html
- **Summary:** Argus NvRaw ( nvargus_nvraw ) is a Bayer raw command-line interface (CLI) capture tool for the Jetson platform. It saves a captured image and its metadata in a file using nvraw format. It can also save a captured image in JPEG, YUV, and headerless raw formats. It accepts user-specified manual exposure control parameters. You can use Argus NvRaw to initiate a capture after auto white balance (AWB) and auto exposure (AE) convergence have been…
- **Sections:** Prerequisites for Use #; Camera Sensor Modes #; nvargus_nvraw Command #; nvargus_nvraw Usage #; Basic Examples #; Displaying Sensor Information #; Capturing Images #; Other Operations #

#### Camera Driver Porting

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/CameraDriverPorting.html
- **Summary:** This topic gives a high-level overview of changes in Jetson Linux release 38 that may impact camera driver development when kernel version 5.10 is replaced by kernel version 6.8. It is intended to assist camera driver developers who must migrate to the new kernel version. For more details, see the source code released with the BSP and the documentation in the BSP distribution’s directory…
- **Sections:** Configuration Changes #; Kernel Version-Specific Code #; dev_err() Function #; I2C API #; NVIDIA Capture Driver Code Path #

#### Camera Software Development Solution

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/CameraSoftwareDevelopmentSolution.html
- **Summary:** This topic describes the NVIDIA ® Jetson™ camera software solution, and explains the NVIDIA-supported and recommended camera software architecture for fast and optimal time to market. It outlines and explains development options for customizing the camera solution for USB, YUV, and Bayer camera support. The NVIDIA camera software architecture includes NVIDIA components that aid development and customization:
- **Sections:** Camera Architecture Stack #; Camera API Matrix #; Approaches for Validating and Testing the V4L2 Driver #; Applications Using libargus Low-Level APIs #; Applications Using GStreamer with the nvarguscamerasrc Plugin #; Applications Using GStreamer with V4L2 Source Plugin #; Applications Using V4L2 IOCTL Directly #; ISP Configuration #

#### Jetson Virtual Channel with GMSL Camera Framework

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/JetsonVirtualChannelWithGmslCameraFramework.html
- **Summary:** This page contains details about the following topics: The Gigabit Multimedia Serial Link (GMSL) protocol.
- **Sections:** Reference Setup #; GMSL Protocol #; GMSL Camera #; CSI Connectivity #; Jetson Thor Series #; Hardware Module Connectivity #; Software Framework and Programming #; Driver Framework #

#### Sensor Software Driver Programming

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/SensorSoftwareDriverProgramming.html
- **Summary:** The camera sensor driver acquires data from the camera’s sensor over the CSI bus, in the sensor’s native format. There are two types of camera programming paths. You must choose one, depending on the camera and your application:
- **Sections:** Camera Core Library Interface #; Direct V4L2 Interface #; Camera Modules and the Device Tree #; To add camera modules to a device tree #; Module Properties #; Individual Imaging Devices #; Device Properties #; Example Piece-Wise Linear Compression Function #

#### Sensor Software Troubleshooting

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/ArgusFramework/SensorSoftwareTroubleshooting.html
- **Summary:** Use the following commands on the target to enable Video Interface (VI) –related tracing through the kernel tracefs interface and NVIDIA ® RTCPU / CamRTC debug nodes. Run as root (or prefix with sudo ). modprobe rtcpu-debug echo 1 > /sys/kernel/debug/tracing/tracing_on echo 30720 > /sys/kernel/debug/tracing/buffer_size_kb echo 1 > /sys/kernel/debug/tracing/events/tegra_rtcpu/enable echo 1 > /sys/kernel/debug/tracing/events/freertos/enable…
- **Sections:** Enabling VI Tracing #; Boost the Clock (for Testing) #

#### Camera Support Matrix

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/CameraDevelopmentSupportMatrix.html
- **Summary:** This topic summarizes camera feature support across NVIDIA Jetson Orin and Jetson Thor platforms. AR0234-based stereo camera module, SmartLead IMX728, SmartLead IMX623

#### Camera SIPL Notifications

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/CameraSIPLNotifications.html
- **Summary:** If triggered, immediately. This event is triggered only if the Auto Exposure and Auto White Balance algorithm produces new sensor settings that need to be updated in the image sensor. Pipeline event: Pipeline forced to drop a frame due to a slow consumer or system issues.
- **Sections:** Power Interrupt Status Codes #

#### Introduction to SIPL

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/Introduction-to-SIPL.html
- **Summary:** The SIPL is NVIDIA’s modular, extensible framework for camera and image sensor integration, image processing, and control, which supports continuous streaming of image data from camera sensors. SIPL provides a unified API and driver model for a wide range of camera hardware. On Jetson Linux (L4T), SIPL supports GMSL and CoE camera systems, including sensors based on the Holoscan Sensor Bridge (HSB). The same core pipeline, Query/Control APIs,…
- **Sections:** SIPL Architecture Overview #; Key Directories (Public Headers and Samples) #; Key Components of SIPL Framework #; SIPL Use Cases #; Benefits and Limitations Compared to Previous Camera Software Architecture #; UDDF #; HSL #; Configuration Using SIPL Query and JSON Database #

#### SIPL Image Formats

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-Image-Formats.html
- **Summary:** SIPL supports multiple image formats using the ICP and ISP outputs. This topic describes how the output formats are set and which parameters you can modify to override output formats under specific conditions. ICP output formats are dependent on the sensor used.
- **Sections:** ICP Output Formats #; ISP Output Formats #; Override Image Attributes #; Examples #

#### Camera HAL Driver Discovery

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/Camera-HAL-driver-discovery.html
- **Summary:** Every UDDF driver library is a .so exporting one C-linkage entry point: uddf_discover_drivers() . CameraHAL scans directories, loads each .so , and matches driver names from platform config to instantiate the right drivers.
- **Sections:** Scan, Load, and Match Drivers from Platform Config #

#### Camera Hardware Abstraction Layer (HAL)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/Camera-HAL.html
- **Summary:** The lifecycle orchestrator — it sits between SIPL (application layer) and your UDDF drivers. CameraHAL is the mediator that ensures your driver never has to coordinate with other drivers directly. You implement interfaces; CameraHAL calls them at the right time with the right context. Loads the right driver — Uses uddf_discover_drivers to fetch DriverInfo.name .
- **Sections:** What does CameraHAL do? #

#### Camera Software Development Solution for Jetson Thor

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/CameraSoftwareDevelopmentSolutionThor.html
- **Summary:** This documentation provides a comprehensive guide to NVIDIA ® Jetson™ camera software solution on the Jetson Thor platform. It outlines and explains the new Safe Image Processing Library (SIPL) framework and the development options for camera applications and sensor drivers for Camera over Ethernet (CoE) solutions. The content is organized to take you from understanding the basic concepts to implementing custom camera solutions using the SIPL…
- **Sections:** Getting Started #; Development Guides #; Configuration and Tools #; Application Development #; Sensor Programming with Python Development Tools #; Sensor Driver Development #; Reference Documentation #; SIPL Notifications #

#### Camera-over-Ethernet Overview

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/CoE-Solution-Overview.html
- **Summary:** Camera-over-Ethernet (CoE) is NVIDIA’s next-generation camera connectivity solution, enabling high-performance, flexible, and scalable camera integration using standard Ethernet networks. CoE is fully supported in the Safe Image Processing Library (SIPL) framework, which provides a unified API and driver model to support seamless bring-up of Holoscan Sensor Bridge (HSB)–based cameras.
- **Sections:** CoE as a Replacement for VI and NVCSI #; CoE Software Architecture #; Software Flow: Steps in CoE Operation #; CoE Data and Control Path Flow #; UDDF and HSL in the CoE Control Path for Camera Drivers #; Camera and Transport Configuration #

#### CoE Camera Development Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/CoECameraDevelopment.html
- **Summary:** This section describes the camera software solution using Camera over Ethernet (CoE) architecture included in NVIDIA ® Jetson™ Linux.

#### Holoscan Sensor Bridge (HSB)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/CoE/Holoscan-Sensor-Bridge.html
- **Summary:** The Holoscan Sensor Bridge (HSB) is an FPGA-based interface developed by NVIDIA to enable real-time, low-latency streaming of sensor data over Ethernet directly into GPU memory for processing. Peripheral device data is acquired by the HSB device FPGA and sent over Ethernet to the host system (the Jetson Thor platform). HSB is a key part of Camera over Ethernet (CoE) bring-up on Jetson when sensors use the CSI-to-Ethernet bridge model…

#### GMSL Architecture Overview

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSL-Architecture-Overview.html
- **Summary:** Gigabit Multimedia Serial Link (GMSL) is the predominant camera connectivity technology for automotive and robotics platforms. GMSL carries full-resolution video over a single coaxial or shielded twisted-pair cable with bidirectional control signaling on the same wire. On NVIDIA platforms, the SIPL framework abstracts GMSL hardware through the Unified Device Driver Framework (UDDF), so application code sees a uniform camera API regardless of…
- **Sections:** Hardware Topology #; UDDF Driver Types #; Link Modes #; PHY Mode and CSI Rates #; Frame Sync #; Serdes Initialization Sequence #; Multi-Camera Systems #

#### Directory Layout and Build

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSL-Directory-Layout-Build.html
- **Summary:** This page summarizes a typical UDDF driver tree layout on disk and how it ties into the CMake build for GMSL camera drivers. Module MyModule with sensor, serializer, EEPROM; plus standalone deserializer and power drivers.
- **Sections:** UDDF Directory Layout #; Build Target Renames #; CMake Build Layout (CMakeLists) #; Sensor Driver (Static Library) #; Module Driver (Static Library) #; Module Library (Shared .so File) #

#### Integrating GMSL UDDF Drivers with SIPL

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSL-SIPL-Integration.html
- **Summary:** This page explains how to make your GMSL UDDF drivers discoverable to the Safe Image Processing Library (SIPL). The integration mechanism is the same for all UDDF driver types: name matching between the DriverInfo.name exported by the driver library and specific fields in the SIPL JSON configuration. For the general UDDF driver model, see Guide to Writing UDDF Drivers . For the CoE driver integration pattern, see Integrating UDDF Drivers with…
- **Sections:** Driver Name Matching #; Example: Deserializer Driver #; Example: Power Drivers #; Example: Camera Module Driver #; Driver Library Entry Point #; Installation Path #; Multiple Driver Libraries #; Verification #

#### Guide to Writing GMSL UDDF Drivers

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSL-UDDF-Driver-Guide.html
- **Summary:** This guide explains how to implement UDDF drivers for GMSL camera systems. It covers all five driver types and uses runnable sample code drawn directly from sipl/uddf/samples/drivers/gmsl/ and sipl/uddf/samples/drivers/gmslpower/ . Before reading this guide, you should be familiar with the UDDF driver model described in Guide to Writing UDDF Drivers and the GMSL topology described in GMSL Architecture Overview .
- **Sections:** Overview of Driver Types #; Deserializer Driver (IGmslDeserializer) #; Class Declaration #; Entrypoint Reference #; DeserializerContext Fields #; Camera Module Driver (IGmslModuleControl) #; Stereo FSYNC Hooks #; GmslModuleContext Fields #

#### GMSL Camera Development Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/GMSL/GMSLCameraDevelopment.html
- **Summary:** This documentation provides a comprehensive guide to Gigabit Multimedia Serial Link (GMSL) camera development using the NVIDIA SIPL framework and Unified Device Driver Framework (UDDF) on supported NVIDIA Jetson platforms, including the Jetson AGX Thor and Jetson Orin families. It covers the GMSL hardware topology, the UDDF DDI interfaces that drivers must implement, the Sensor System Config JSON schema used to describe GMSL hardware, and a…
- **Sections:** Module Driver #; Sensor Driver #; Serializer Driver #; Deserializer Driver #; Deserializer Power #; Module Power (PMIC) #; Getting Started #; Development Guides #

#### SIPL Camera Application Developer Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-App-Development-Guide.html
- **Summary:** Camera driver source package for Jetson L4T platforms. It contains UDDF device drivers for GMSL and Camera-over-Ethernet (CoE) camera modules, plus SIPL sample applications to capture and display camera frames. This package is a companion to the NVIDIA SIPL Camera Driver Release Documentation , which covers architecture, APIs, platform configuration, and advanced topics in detail. Refer to it for anything beyond build-and-run basics.
- **Sections:** NVIDIA SIPL Camera Driver Package #; Repository Layout #; Build Prerequisites #; Building the Package #; CMake Options for Applications #; Key Build Outputs #; Installing on the Target #; Running Sample Applications #

#### SIPL Query JSON Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-JSON-Query-Guide.html
- **Summary:** This guide describes how to author SIPL Query JSON databases for GMSL and Camera over Ethernet (CoE) camera systems on NVIDIA Jetson platforms. CoE and GMSL use the same SIPL Query APIs (see sipl/include/query/include/NvSIPLCameraQuery.hpp ); the JSON layout and file layout differ by transport. JetPack 7.2 JSON config change: Case-sensitive “name” fields. As of JetPack 7.2, module, transport, sensor, serializer, and deserializer "name" fields…
- **Sections:** What Is SIPL Query? #; SIPL Query API Overview #; GMSL Camera Development #; JSON File Categories #; Platform Transport Settings #; Sensor System Config #; Component Database Files #; Name Matching Rules #

#### JetPack 7.2 SIPL Migration Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-Migration.html
- **Summary:** This page summarizes the customer-visible migration items when moving SIPL applications, UDDF drivers, and SensorSystemConfig JSON files from JetPack 7.1 to JetPack 7.2. JetPack installs the released SIPL API files under /usr/src/jetson_sipl_api/sipl . Examples in this guide use sipl/ as the source-tree root.
- **Sections:** Package Layout, Build, and Install Changes #; Query and Configuration API Changes #; SensorSystemConfig JSON Changes #; SIPL Notifications and Metadata #; UDDF Driver Migration #; Stereo and FSYNC Updates #; Other Public API Additions #; Migration Checklist #

#### SIPL Query Sample

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-Query-sample.html
- **Summary:** Sample application demonstrating the INvSIPLCameraQuery API with the SensorSystemConfig structure. It works with both GMSL and CoE (Camera over Ethernet) camera configurations. For JSON schema and query database details, see SIPL Query JSON Guide .
- **Sections:** Requirements #; Building #; Usage #; Bare Run (No Arguments) #; Command-Line Options #; Display Modes #; Legacy-Style (Bare Run) #; Hierarchical (with -c , -m , -s , -d ) #

#### SIPL Stereo Pipeline

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/SIPL-Stereo-Pipeline.html
- **Summary:** Stereo has been demonstrated with the AR0234-based HAWK stereo camera module. In stereo mode, the left sensor is treated as the primary sensor and the right sensor as the secondary sensor. Both sensors are synchronized through external FSYNC; the secondary sensor reuses the primary sensor’s ISP settings and auto-control output to keep the stereo pair operating with common ISP and auto-control behavior(to maximize the parity between the two…
- **Sections:** JSON Configuration for Stereo #; Example: Stereo Configuration ( ar0234_hawk.json ) #; Example: CoE Stereo Configuration ( VB1940_Stereo ) #; External FSYNC Signal Chain #; Stereo Pipeline Lifecycle (Primary and Secondary Sensors) #

#### UDDF

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/UDDF.html
- **Summary:** Unified Device Driver Framework documentation for camera driver development with SIPL.

#### FAQ

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/faq.html
- **Summary:** No. You need Python only for PyHSL, which compiles HSL sequences offline. You can build the bytecode for those sequences directly into your drivers. UDDF never invokes Python at runtime. HSL is a simple language. An HSL sequence cannot behave conditionally, nor can it perform any other type of computation. If you want your driver to behave differently based on hardware revision or any other variation in hardware, you need logic outside of any…
- **Sections:** Does Use of HSL Require Python at Runtime? #; Why Would You Dynamically Generate HSL in the Driver? #

#### HSL and UDDF Overview

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/overview.html
- **Summary:** The Unified Device Driver Framework (UDDF) is a framework for writing user-mode drivers to control camera hardware. UDDF has the following goals: Enable NVIDIA partners to develop high-quality, safety-certifiable drivers.
- **Sections:** UDDF Basics #; HSL Basics #; UDDF/HSL Integration #

#### PyHSL

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/pyhsl/PyHSL.html
- **Summary:** Developer Guide page: PyHSL.

#### PyHSL Programmer Guide

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/pyhsl/pyhsl_guide.html
- **Summary:** PyHSL is a high-level language for constructing HSL sequences. PyHSL is Python with a set of support classes and functions, and the “compilation” of a PyHSL program is simply execution of the main() function provided in the source file. That execution produces one or more HSL bytecode sequences, packaged into a single output file in HSLC format. Static HSL (HSL blob compiled and available at build time). #
- **Sections:** Introduction #; Usage #; Command-Line Parameters #; Program Structure #; PyHSL Objects #; I2CDevice #; Sequence #; GPIOPin #

#### PyHSL Reference

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/pyhsl/pyhsl_ref.html
- **Summary:** I2CDevice(address, offset_width, data_width, name, auto_retry=False, ten_bit_address=False, no_virtual_address=False) offset_width is the number of bits used to specify an offset for this device. Currently, this must be either 8 or 16.
- **Sections:** I2CDevice methods #; constructor #; poll #; readDiscard #; readToMemory #; readVerify #; readVerifyFromMemory #; readVerifyStream #

#### Release Notes

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/release_notes.html
- **Summary:** Known issues, missing features, and changes for the current release. The following features are not yet available in UDDF. If your driver relies on any of these, the corresponding functionality will arrive in a future release.
- **Sections:** Not Yet Supported #

#### Integrating UDDF Drivers with SIPL

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/sipl_integration.html
- **Summary:** After you build your UDDF driver, you must make it discoverable by SIPL. This page covers driver configuration matching, the JSON configuration structure, and the library installation path that SIPL scans at startup. SIPL uses a name-matching system to connect your drivers with camera configurations. The DriverInfo.name in your driver code must exactly match the corresponding name field in the platform’s SensorSystemConfig JSON files.
- **Sections:** Driver Configuration Matching #; In Your Driver Code #; In Your SensorSystemConfig JSON #; Driver Library Installation #

#### Guide to Writing UDDF Drivers

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/Guide-to-Writing-UDDF-Drivers.html
- **Summary:** This guide covers the UDDF driver model, driver interfaces and lifecycle, practical development guidance, and how to use HSL for hardware access.

#### Discovery and Enumeration

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/discovery.html
- **Summary:** UDDF loads driver libraries ( .so files) at runtime through dynamic linking. A driver library is a shared library that contains one or more driver implementations. Each library exports a single C-linkage entry point, and through that entry point the library advertises the drivers it contains so UDDF can instantiate them on demand. The UDDF Driver Model page introduced a minimal single-driver enumerator for the CAM123 example. This page covers…
- **Sections:** The Entry Point #; DriverInfo #; IDriverEnumerator #; Multi-Driver Libraries #; Different Driver Classes #; Driver Variations #

#### UDDF Driver Model

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/driver_model.html
- **Summary:** The UDDF driver model is built on two concepts: driver interfaces and driver objects. A driver interface is a C++ class that defines only pure virtual methods. It contains no data and no implementation. Interfaces provide all communication between a driver and its environment. Driver interfaces come in two flavors:
- **Sections:** Device Driver Interface (DDI) #; Driver Interfaces #; Driver Objects #; Driver Lifecycle #; CAM123 Lifecycle Methods #; Camera Driver Interface (CDI) #; Context Structures #; HSL and the Build System #

#### CAM123 Driver Template

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/driver_template.html
- **Summary:** This page provides the complete files for the fictional CAM123 driver from the UDDF Driver Model page, assembled into a copy-paste starting template. No new concepts are introduced here—refer to the Driver Model page for explanations.
- **Sections:** ICam123Control.hpp #; Cam123Driver.cpp #; cam123_hsl.py #; Makefile #

#### GMSL

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/gmsl.html
- **Summary:** Gigabit Multimedia Serial Link (GMSL) is the predominant camera connectivity technology for automotive platforms and is increasingly adopted in robotics. A typical GMSL camera topology places one deserializer on the SoC side and one or more camera modules on the remote end of each link. Each camera module contains a serializer, a sensor, and optional components such as an EEPROM or PMIC. A high-speed GMSL link connects each module to the…
- **Sections:** GMSL Overview #; Deserializer Drivers #; Camera Module Drivers #; Module Sub-Components #; Power Drivers #; Serdes Initialization Sequence #; I2C Addressing #; Physical Address Remapping #

#### GMSL Building Blocks (UBB)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/gmsl_ubb.html
- **Summary:** UDDF Building Blocks (UBB) is an optional convenience layer for GMSL camera module drivers. It reduces the boilerplate required to implement the standard IGmslModuleControl and IModuleComponentAccess interfaces by letting you compose a module driver from reusable component classes: one for the sensor, one for the serializer, and optionally one for an EEPROM. UBB does not add new behavior. Everything it does is achievable with the raw UDDF DDI…
- **Sections:** When to Use UBB #; What UBB Provides #; What UBB Does Not Provide #; Architecture #; Lifecycle Hooks #; Writing a Module Driver with UBB #; Step 1 – Create Component Classes #; Step 2 – Create the Module Driver #

#### Using HSL in UDDF

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/UDDF/uddf_drivers/hsl_toolchain.html
- **Summary:** Hardware Sequence Language (HSL) is a simple language for specifying I2C and GPIO hardware accesses. HSL has no conditionals, no arithmetic, and no control flow—it encodes a flat list of hardware operations that the framework executes in order. The standard source language for HSL is PyHSL , a Python DSL that compiles to HSL bytecode. Static HSL: Sequences are authored in PyHSL and compiled ahead of time. The resulting bytecode is embedded…
- **Sections:** HSL Overview #; Static HSL #; Writing Generic HSL Files and Address Retargeting #; Dynamic HSL #; Memory I/O #; Combining Dynamic and Static HSL #; GPIO Operations #; Debugging HSL Sequences #

#### Runtime Interfaces and Sensor Characterization

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPL-for-L4T/runtime_intf_char_mode.html
- **Summary:** Used for ISP tuning and sensor validation. Validates sensor characteristics, tests linearity of pixel values (RGB) with increasing gain or exposure time, and performs conformance testing. Disable sensor compression / companding (if applied).
- **Sections:** Sensor Characterization Mode #

#### SIPL Framework

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CameraDevelopment/SIPLFramework/SIPLFramework.html
- **Summary:** This section describes the SIPL and related guides for GMSL, CoE, UDDF, HSL, and camera integration on supported NVIDIA ® Jetson™ platforms. For full UDDF comprehensive documentation, refer to UDDF . It includes the driver guide, PyHSL, SIPL integration, migration from CDD, release notes, and FAQs.

### Security

#### Security

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security.html
- **Summary:** This topic describes security features of NVIDIA ® Jetson™ Linux. Secure Boot describes Secure Boot, a feature that ensures the Jetson Linux boot process cannot be redirected or compromised.

#### Disk Encryption

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption.html
- **Summary:** Applies to Jetson AGX Orin, the Jetson Orin NX series, the Jetson Orin Nano series, and the Jetson Thor series. Disk encryption encrypts a whole disk or partition to protect the data it contains. NVIDIA ® Jetson™ Linux offers disk encryption that is based on Linux Unified Key Setup (LUKS) Data-at-rest encryption , It provides a standard disk format that stores all necessary setup information on the disk in the partition header. The passphrase…
- **Sections:** Quick Guide #

#### Disk Encryption Concepts

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption/Concepts.html
- **Summary:** This topic describes the host-side setup, the keys and services used to derive a per-device passphrase, the threat model, and the overall disk-unlocking sequence used by NVIDIA ® Jetson™ Linux disk encryption. Jetson Linux uses cryptsetup , a LUKS user-space command-line utility, to set up and unlock an encrypted disk. It uses the DMCrypt kernel module as its backend. The utility sets up the encrypted disk as a LUKS partition and configures…
- **Sections:** Setup Preparation #; Details of Operation #; Threat Model #; Unlocking Process Summary #

#### Dynamic Partition Encryption

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption/DynamicPartitions.html
- **Summary:** Use this workflow to encrypt a partition at run time—after the device has been flashed and booted—rather than at image-generation time. The device-side helper /usr/sbin/gen_luks.sh converts an existing partition to a LUKS volume and records it in /opt/nvidia/cryptluks so that it is unlocked and mounted on subsequent boots. To encrypt a specific partition at run time, use the /usr/sbin/gen_luks.sh tool. This tool updates the…
- **Sections:** Enabling Disk Encryption for Dynamically Created Partitions #; Modifying /opt/nvidia/cryptluks to Unlock Previously Created and Encrypted File Systems #

#### Encrypting the Rootfs

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption/EncryptingRootfs.html
- **Summary:** These procedures generate, flash, and boot a Jetson device with an encrypted root file system (rootfs). The same tooling covers internal (eMMC) and external (NVMe) rootfs, the UDA-only variant, and the initrd-level customization required to unlock additional encrypted file systems at boot. The rootfs is generated on the host by l4t_initrd_flash.sh . The following diagram shows the inputs (in green), the utilities used to generate it (in…
- **Sections:** Creating an Encrypted Rootfs on the Host #; Flashing an Encrypted Rootfs to an External Storage Device #; Enabling Disk Encryption Only for UDA #; Enhancing initrd to Unlock an Encrypted Rootfs #; Modifying initrd to Unlock Additional Encrypted File Systems #

#### Manufacturing

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption/Manufacturing.html
- **Summary:** Production flashing differs from developer flashing in two important ways: images must be generated once on a secure system and then replicated across many devices, and the generic key used to encrypt those images must be replaced with a per-device unique key on first boot. The following diagram illustrates the post-development manufacturing process for a Jetson-based device.
- **Sections:** Manufacturing Process #; Creating Encrypted Images with a Generic Key #; Replacing the Generic Key with the Per-device Unique Key at First Boot #; (Optional) Encrypting the Disks Again #; Building cryptsetup #

#### Partition Layout

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/DiskEncryption/PartitionLayout.html
- **Summary:** Jetson Linux provides a reference implementation of disk encryption that fulfills the security requirements of many use cases. If your use case’s requirements are different, you can modify the reference implementation or use it as a model for implementing your own. Because Bootloader cannot read encrypted files, disk encryption requires Jetson Linux to divide a “naive” system’s APP partition in two:
- **Sections:** Layout of an Encrypted Disk #

#### Factory Secure Key and Expansion Key Provisioning

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FSKP.html
- **Summary:** Applies to the Jetson AGX Thor series, the Jetson AGX Orin series, the Jetson Orin NX series, and the Jetson Orin Nano series. Factory Secure Key Provisioning (FSKP) is a technique to securely burn fuses on the factory floor. The fuse data contains a sensitive device and encryption keys that establish the root of trust on the target device. FSKP protection is important because the factory floor might not have a high level of security and can…
- **Sections:** Requesting FSKP Keys from NVIDIA #; Generating and Verifying the Self-Signed X.509 Certificate #; Generating an RSA Key Pair and Creating a Certificate with the Public Key (Option 1 with keytool) #; Generating an RSA Key Pair and Creating a Certificate with the Public Key (Option 2 with OpenSSL) #; Content of the Results.zip File #; An Example: Preparing the Encrypted and Signed Blob at HSM #; Preparing the Encrypted and Signed Blob #; An Example: Using the Encrypted and Signed Blob at the Factory #

#### Firmware TPM

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM.html
- **Summary:** Applies to the Jetson AGX Thor series, the Jetson AGX Orin series, the Jetson Orin NX series, and the Jetson Orin Nano series. Before you begin, reference the Trusted Computing Group (TCG) website to familiarize yourself with the Trusted Platform Module (TPM) specification:

#### Software Architecture

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/Architecture.html
- **Summary:** The TPM component, either fTPM or a hardware-based discrete TPM (DTPM), relies on the TPM Software Stack (TSS) to communicate with the TPM. The fTPM software architecture includes an fTPM TA running in OP-TEE with TSS support in the non-secure world. TSS: User space applications depend on TSS to utilize the secure functionalities of the TPM. TSS combines multiple layers, including application-level APIs, underlying communication interfaces,…
- **Sections:** Non-secure World #; Secure World #

#### fTPM Boot Flow

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/BootFlow.html
- **Summary:** The fTPM boot flow verifies and measures the integrity of firmware components during the boot process. Secure Boot is an essential part of the fTPM boot flow. It ensures that only authorized firmware components are loaded during the boot process and establishes Hardware Root of Trust (HROT), Root of Trust for Reporting (RTR), and Root of Trust for Measurement (RTM). The purple line in the diagram shows the Secure Boot flow, indicating that…
- **Sections:** fTPM Secure Boot #; fTPM Measured Boot #

#### Device-Side Operations

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/DeviceOperations.html
- **Summary:** The fTPM provisioning script handles provisioning of the fTPM on NVIDIA Jetson™ devices. This process involves querying EK certificates from the Encrypted Key Block (EKB), storing the EK certificate in fTPM non-volatile (NV) memory, taking ownership of the fTPM, and creating EKs with default EK handles. The fTPM helper TA/CA and PTA are applications designed to support fTPM provisioning, providing interfaces for querying SN and EK certificates.
- **Sections:** Running the fTPM Provisioning Script #; Rebuilding and Updating the TOS Image #; Automatic Provisioning During Boot #; Manual Provisioning #; Generating the fTPM Measurement List #; PCR0 Measurement List (Jetson Boot Chain) #; UEFI PCR Measurements (PCR1–PCR8 and Other PCRs) #; Validating Measurement Results #

#### Production Workflow

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/ProductionWorkflow.html
- **Summary:** This section provides the tools, templates, and step-by-step procedures for fTPM production when a single entity plays both the ODM and OEM roles. It covers everything from BSP installation through factory flashing. For the conceptual design and the architectural tolerance that allows ODM and OEM to be two separate entities, refer to fTPM Production Flow .
- **Sections:** Jetson BSP Installation #; Server Setup for fTPM Production Scripts #; Prerequisites for Enabling fTPM #; KDK Database and Fuseblob Generation #; Generating kdk-db and Silicon ID Public Keys #; Fuse Configuration Templates #; Generating Fuseblobs #; EKB Generation #

#### fTPM Provisioning

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/Provisioning.html
- **Summary:** A fundamental difference exists between a DTPM and fTPM. A DTPM or TPM chip has been provisioned by the TPM vendor or manufacturer with the Endorsement Key (EK) certificate, which serves as the TPM identification for attestation. Without this certificate, trust between the TPM user and services that rely on TPM cannot be established. To create a trustworthy fTPM entity on different devices, you must provision it with a per-device unique ID…
- **Sections:** Preparation Before Provisioning (Offline Method) #; Prerequisites of the fTPM Vendor #; Signing the EK CSRs #; Generating Per-Device EKB #; Key Derivation Process #; Silicon ID Provisioning Flow in Secure Boot #; EPS Derivation Flow in the OP-TEE OS Layer #; fTPM Production Flow #

#### fTPM Turnkey Solution for Ecosystem Partners

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/FirmwareTPM/TurnkeySolution.html
- **Summary:** To streamline fTPM provisioning during the manufacturing flow, we offer a turnkey solution designed to simplify the process and reduce the burden on manufacturing operations. SecEdge collaborated with NVIDIA to develop a firmware Trusted Platform Module (fTPM) solution, named SEC-TPM, which provides in-field trust provisioning and management for the NVIDIA JetPack SDK. This industry-first solution offers a secure root-of-trust in an NVIDIA…

#### Hafnium Secure Partition Manager

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/Hafnium.html
- **Summary:** Hafnium is an open-source secure partition manager (SPM) implementation based on the Arm Firmware Framework for Arm A-profile (FF-A) specification. It runs at S-EL2 and is responsible for managing secure partitions in the secure world. Provides isolated execution environments for secure partitions.
- **Sections:** Architecture Components #; CPU Topology Configuration #; CPU Node Structure #; CPU Node Properties #; CPU Identifier Format #; CPU Configuration Considerations #; Secure Partition Configuration #; Basic Partition Configuration #

#### Security Keys List

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/KeyList.html
- **Summary:** Applies to the Jetson AGX Thor series, the Jetson AGX Orin series, the Jetson Orin NX series, and the Jetson Orin Nano series. Signs/authenticates boot components in the secure boot chain (root-of-trust ultimately anchored by fused public key hashes).
- **Sections:** PKC/SBK Keys / Secure Boot (BootROM → MB stages → UEFI) #; UEFI Secure Boot Keys (PK/KEK/db/dbx) #; UEFI Payload Encryption and Variable Protection #; Platform Vendor (PV) Keys #; Factory Secure Key Provisioning (FSKP) #; EKB (Encrypted Key Blob) Generation Keys #; OP-TEE Keys #; Secure Storage Keys #

#### Memory Encryption

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/MemoryEncryption.html
- **Summary:** Applies to the Jetson AGX Orin series, Jetson Orin NX series, Jetson Orin Nano series, and Jetson AGX Thor series. The Memory Subsystem (MSS) provides 128-bit AES-XTS encryption functionality for data stored in DRAM to protect secure content from hardware snooping attacks. Write data stored in certain regions of DRAM (MTS, TZ, and GSC carveouts on Jetson Orin and TZ and GSC carveouts on Jetson Thor) is encrypted before reaching the DRAM. Read…
- **Sections:** Jetson Orin Memory Encryption #; Jetson Thor Memory Encryption #

#### OP-TEE: Open Portable Trusted Execution Environment

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee.html
- **Summary:** Applies to the Jetson AGX Thor series, the Jetson AGX Orin series, the Jetson Orin NX series, and the Jetson Orin Nano series. Open Portable Trusted Execution Environment (OP-TEE) is an open-source trusted execution environment (TEE) based on Arm® TrustZone® technology , created by trustedfirmware.org , and maintained by Linaro .
- **Sections:** OP-TEE in Jetson Linux #

#### Architecture

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee/Architecture.html
- **Summary:** OP-TEE resides in a separate storage partition and boots as part of a chain of trust or a secure boot sequence. It creates two environments in a device with different security modes: Non-Secure Environment (NSE): An environment for running software components in non-secure mode. This environment constitutes the “normal world.” A rich OS, such as Linux, typically runs in this environment.
- **Sections:** Execution Steps #

#### EKB: Encrypted Key Blob

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee/Ekb.html
- **Summary:** Different security functions often need different types of keys to encrypt, decrypt, authenticate, and verify data. These keys are usually confidential and sensitive, and compromising them would have serious consequences. As a complement to fuses, the Encrypted Key Blob (EKB) provides additional storage for security keys and data. Its usage is completely defined by the user, making it flexible and scalable. The EKB is encrypted by the EKB…
- **Sections:** Terminology #; EKB Fuse Key #; Key Distribution System (KDS) #; Keyslot #; TZ Root Key (TZ_RK) #; EKB Root Key (EKB_RK) #; EKB Encryption Key (EKB_EK) #; EKB Authentication Key (EKB_AK) #

#### PKCS #11 Support in OP-TEE

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee/Pkcs11.html
- **Summary:** In cryptography, PKCS #11 is one of the Public-Key Cryptography Standards and refers to the programming interface used to create and manipulate cryptographic tokens, where the secret is a cryptographic key. The PKCS #11 standard defines a platform-independent API for interacting with cryptographic tokens, such as hardware security modules (HSM) and smart cards. The API is officially named Cryptoki (derived from “cryptographic token interface”…
- **Sections:** Cryptoki Introduction #; Token Management #; Key Management #; Encryption and Decryption #; Cryptoki Implementation in OP-TEE #; PKCS #11 TA #; PKCS #11 Sample CA #

#### Sample Applications

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee/SampleApplications.html
- **Summary:** The following diagram shows an overview of secure sample applications provided by Jetson Linux: Three CAs and TAs: hwkey-agent TA and luks TA with corresponding CAs in the normal-world user space, and cpubl-payload-dec TA with the corresponding CA in L4T Launcher.
- **Sections:** Jetson User Key PTA #; EKB Key Management #; User Key Services #; Random Number Generator #; Key Derivation Function #; CPUBL Payload Decryption Services #; HWKEY AGENT CA and TA #; Data Encryption and Decryption #

#### Trusted Application and Client Application Development

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/OpTee/TaCaDevelopment.html
- **Summary:** This section gives a brief overview of the OP-TEE Trusted Application and Client Application (TA/CA) architecture. The OP-TEE TA/CA is a client-server model that follows the GlobalPlatform TEE API. The Client Application uses the TEE Client API to invoke the Trusted Application service in the secure world. The Trusted Application implements the service using functions defined by TEE Internal Core API Specification.
- **Sections:** Cross-Compiling a Trusted Application #; Implementing or Porting a Trusted Application #; Types of Trusted Applications #; Signing of Trusted Applications #; Subkeys #

#### PVA Authentication

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/PVAAuthentication.html
- **Summary:** Applies to the Jetson AGX Orin series, Jetson Orin NX series, Jetson Orin Nano series, and Jetson AGX Thor series. The Programmable Vision Accelerator (PVA) is a specialized engine to accelerate computer vision and image processing tasks. Specialized software libraries such as VPI utilize the PVA.
- **Sections:** Overview #; Troubleshooting #

#### Rollback Protection

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/RollbackProtection.html
- **Summary:** Applies to the Jetson AGX Orin series, Jetson Orin NX series, Jetson Orin Nano series, and Jetson AGX Thor series. Rollback protection prevents a computing system from being downgraded (rolled back) from a later version to an earlier one.
- **Sections:** Overview #; Rollback Protection for MB1-BCT, MB2, and Later Components #; MB1-BCT #; MB2 and Later Components #; Incrementing the Version Number of MB2 and Later Components #

#### Secure Boot

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot.html
- **Summary:** NVIDIA ® Jetson™ Linux provides boot security. Secure Boot prevents execution of unauthorized boot codes through the chain of trust. The root-of-trust is an on-die BootROM code that authenticates boot codes such as BCT, Bootloader, and warm boot vector using Public Key Cryptography (PKC) keys stored in write-once-read-multiple fuse devices. On Jetson platforms that support Secure Boot Key (SBK), you can use it to encrypt Bootloader images.…
- **Sections:** Overall Fusing and Signing Binaries Flow #; Quick Start Guides #; Jetson Thor #; Jetson Orin #; Prerequisites for Secure Boot #; Fuses and Security #

#### Fuse Configuration File

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/FuseConfiguration.html
- **Summary:** The fuse configuration file, which is an XML file, contains the fuse data, a list of fuses, and the value to be burned in each fuse. The fskp_fuseburn.py tool uses this XML file to program the fuses.
- **Sections:** Jetson Thor Fuse Configuration File #; Generate a PKC Key List for Jetson Thor #; Examples of Jetson Thor Fuse Configuration Files #; Jetson Thor Reference Fuse Configuration File #; Generate a PKC Key Pair for Jetson Thor #; Generate PublicKeyHash Value From a PKC Key List for Jetson Thor #; Jetson Orin Fuse Configuration File #; Examples of Jetson Orin Fuse Configuration Files #

#### Fuse Operations

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/FuseOperations.html
- **Summary:** After the Fuse Configuration file is prepared, you can burn fuses using odmfuse.sh (-X option) script with the Fuse Configuration file: sudo ./odmfuse.sh -X <fuse_config> -i <chip_id> <target_config> If a Jetson board was previously burned with a PKC key <pkc.pem>, and the board needs to have additional fuses burned, run the following odmfuse.sh command with -k option:
- **Sections:** Burn Fuses with the Fuse Configuration file #; Read Fuses through the Linux kernel #

#### Kernel Module Signing

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/KernelModuleSigning.html
- **Summary:** The kernel module signing facility signs modules during installation and then checks the signature upon loading the module. This allows increased kernel security by disallowing the loading of unsigned modules or modules that were signed with an invalid key. Here are the kernel configure options for kernel module signing:

#### Key Preparation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/KeyPreparation.html
- **Summary:** An SBK key is used to encrypt Bootloader components. The same SBK key has to be fused to the Jetson’s SoC fuses, so the key can be used to decrypt the Bootloader components when the Jetson device boots up. You can only use the SBK key with the PKC key. The encryption mode that uses these two keys together is called SBKPKC.
- **Sections:** Prepare an SBK key #; Prepare K1/K2/KDK1 Keys #; For the Jetson Thor series #; For the Jetson Orin series #; Sample Fuse Key #; Prepare EKB #; Prepare the Fuse Configuration file #

#### PKC Key Revocation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/PkcKeyRevocation.html
- **Summary:** The Jetson Thor SoC supports 16 PKC public keys and provides a revoking mechanism if keys are compromised after the product is shipped. The Jetson Thor SoC is capable of revoking multiple keys at the same time. Only the first 15 PKC keys are revocable. The last PKC key ( key_id="15" ) cannot be revoked. If a key used in an inactive boot chain is listed for revocation, the Jetson Thor SoC will not revoke it. This prevents the inactive boot…
- **Sections:** Revocation of PKC Keys for Jetson Thor #; An Example: Revoke PKC keys 0, 1, and 5 #; Revocation of PKC Keys for Jetson Orin #; An Example: Fusing the Three PKC keys #; An Example: Revoking the First PKC key (rsa3k-0.pem) #; An Example: Revoking the Second PKC key (rsa3k-1.pem) #

#### UEFI Platform Vendor Key Feature

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/PlatformVendorKey.html
- **Summary:** The UEFI platform vendor (PV) key feature allows PVs to deploy UEFI that is signed and encrypted by PV-owned keys without involving the solution providers. The component at stage N verifies the components at stage N+1.
- **Sections:** Platform Vendor Key Sign/Authenticate UEFI #; Platform Vendor Procedure #; Solution Provider Procedure #; PV Key Encrypt/Decrypt UEFI (Only for Jetson Orin Series) #; Fuse Solution #; Fuse handling #

#### Quick Start Guide to Enable Secure Boot for Jetson Orin

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/QuickStartOrin.html
- **Summary:** This guide describes how to enable Secure Boot on a Jetson Orin device, covering environment setup, key generation, fuse burning, EKB image preparation, UEFI key enrollment, QSPI signing and flashing, and OS installation. To follow this guide, we recommend opening two terminal windows:
- **Sections:** Environment Setup #; Requirements #; Pre-UEFI #; Preparing the PKC Keys #; Prepare the Fuse Configuration File #; Fuse the Board #; Preparing the EKB Image #; Secure UEFI #

#### Quick Start Guide to Enable Secure Boot for Jetson Thor

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/QuickStartThor.html
- **Summary:** This guide describes how to enable Secure Boot on a Jetson Thor device, covering environment setup, key generation, fuse burning, EKB image preparation, UEFI key enrollment, QSPI signing and flashing, and OS installation. To follow this guide, we recommend opening two terminal windows:
- **Sections:** Environment Setup #; Requirements #; Pre-UEFI #; Prepare the PKC Keys #; Prepare the Fuse Configuration File #; Fuse the Board #; Prepare the EKB Image #; Secure UEFI #

#### Sign and Flash Secured Images

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/SignAndFlash.html
- **Summary:** The procedures described in this section use the following placeholders in their commands: <pkc_keyfile> is a PKC key file (RSA 3K, ECDSA P-256, ECDSA P-521, or XMSS) used for Orin series.
- **Sections:** Sign and Flash in One Step Using the l4t_initrd_flash.sh Script #; Sign and Flash in Separate Steps Using the l4t_initrd_flash.sh Script #

#### UEFI Payload Encryption

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/UefiPayloadEncryption.html
- **Summary:** UEFI Payload Encryption is not supported for the Jetson Thor series. UEFI Payload Encryption encrypts UEFI payloads. This security measure requires the use of a specific UEFI payload encryption key, which is user-defined and stored in the encrypted key blob, then flashed onto the encrypted key store (EKS) partition.
- **Sections:** Prepare the User Encryption Key #; Generate the EKB #; Enable UEFI Payload Encryption During the Flashing Process #; Using the --uefi-enc <user_encryption.key> Option to Provide the User Encryption Key and Enable UEFI Payloads Encryption #

#### UEFI Secure Boot

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/UefiSecureBoot.html
- **Summary:** UEFI Secure Boot uses digital signatures (RSA) to validate the authenticity and integrity of the codes that it loads. UEFI Secure Boot implementations use PK, KEK, and db keys:
- **Sections:** Prerequisites #; References #; Prepare the PK, KEK, db Keys #; Generate the PK, KEK, and DB RSA Key Pairs, Certificates and EFI Signature List Files #; Generate the UEFI Secure Boot DTBO #; Enable the UEFI Secure Boot #; Method One: Enable UEFI Secure Boot at Flashing Time #; Method Two: Enable UEFI Secure Boot Using Capsule Update #

#### UEFI Variable Protection

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureBoot/UefiVariableProtection.html
- **Summary:** UEFI Variable Protection secures UEFI variables against tampering. This security measure requires the use of a specific UEFI variable authentication key, which is user-defined and stored in the EKB then flashed onto EKS partition. When the system boots into OP-TEE, the user key PTA extracts this key from EKB. When the system boots into UEFI, UEFI will call the TA to use the UEFI variable authentication key for calculating a measurement that…
- **Sections:** Prepare the UEFI Variable Authentication Key #; Generate the EKB #; Enable UEFI Variable Protection During the Flashing Process #

#### Secure Storage

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Security/SecureStorage.html
- **Summary:** Applies to the Jetson AGX Thor series, Jetson AGX Orin series, the Jetson Orin NX series, and the Jetson Orin Nano series. The Jetson Linux implementation of Secure Storage is provided by OP-TEE . Secure Storage is a solution to store general-purpose data and key material and guarantees confidentiality and integrity of the data stored and the atomicity of the operations that modifies the storage. Atomicity means that either the entire…
- **Sections:** Secure Storage in Jetson Linux #; Hardware Unique Key (HUK) #; Secure Storage Implementations #

### Communications & platform

#### Boot Time Optimization

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/BootTimeOptimization.html
- **Summary:** NVIDIA ® Jetson™ Linux provides a generic BSP for developing your product. To decrease boot time, customize the provided BSP components based on the requirements of your product. For a Jetson AGX Orin™ Developer Kit running NVIDIA JetPack™ 6.0, boot from the internal QSPI and eMMC with the default configuration. The average time from a cold power-on to the login prompt is approximately 43 seconds. By applying the following optimization…
- **Sections:** Disable MB1/MB2 Logs #; Modify Combined UART #; Modify UEFI Components #; Kernel Optimization #; Enable Service #; Check Profiler Entries #

#### Communications

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Communications.html
- **Summary:** This topic describes several special features that NVIDIA ® Jetson™ Linux provides for communication with other devices and the end user: PCIe Endpoint Mode describes a facility for communicating with another device through a shared PCIe bus.

#### Audio Setup and Development

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Communications/AudioSetupAndDevelopment.html
- **Summary:** This topic concerns the ASoC driver, audio hub hardware, USB audio, and other matters connected with audio on NVIDIA ® Jetson™ devices. Advanced Linux Sound Architecture ( ALSA ) provides audio functionality to the Linux operating system. The NVIDIA ALSA System-on-Chip ( ASoC ) drivers enable ALSA to work seamlessly with different NVIDIA SoCs. Platform-independent and generic components are maintained by the upstream Linux community.
- **Sections:** ASoC Driver for Jetson Products #; ALSA #; DAPM #; Device Tree #; ASoC Driver #; Audio Hub Hardware Architecture #; Chip-specific Information #; ASoC Driver Software Architecture #

#### Enabling Bluetooth Audio

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Communications/EnablingBluetoothAudio.html
- **Summary:** Hardware support for Bluetooth ® audio varies by platform. The following table summarizes the support provided in each case: * Through M.2 key E connector. Customer must supply Bluetooth hardware except as noted for individual modules.
- **Sections:** To enable Bluetooth audio #

#### PCIe Endpoint Mode

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Communications/PcieEndpointMode.html
- **Summary:** Jetson Linux contains the following software support for PCIe endpoint mode: A Linux kernel device driver for the PCIe endpoint controller.
- **Sections:** Hardware Requirements #; Flashing PCIe as Endpoint on a Jetson AGX Orin Series System #; Flashing PCIe as Endpoint on a Jetson Orin NX/Nano Series System #; Connecting and Configuring the Devices #; Testing Procedures #; Prepare for Testing #; Execution #

#### Platform Power and Performance

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/PlatformPowerAndPerformance.html
- **Summary:** This section describes power and performance management features of NVIDIA ® Jetson™ devices supported by this release of Jetson Linux. It describes the power, thermal, and electrical management features visible to software, as well as some tools and related techniques.

#### Jetson Orin Nano Series, Jetson Orin NX Series, and Jetson AGX Orin Series

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonOrinNanoSeriesJetsonOrinNxSeriesAndJetsonAgxOrinSeries.html
- **Summary:** This topic describes power and performance management features of NVIDIA ® Jetson Orin™ Nano series, Jetson Orin™ NX series, and NVIDIA ® Jetson AGX Orin™ series devices. It describes the power, thermal, and electrical management features visible to software, as well as some tools and related techniques. The power management features of these devices are very similar, and most of this document applies equally to all. For convenience, the text…
- **Sections:** Interacting Features #; Kernel Space Power Saving Features #; Chipset Power States #; Clock and Voltage Management #; Regulator Framework #; CPU Power Management #; Frequency Management with cpufreq #; Idle Management with cpuidle #

#### Jetson Thor Product Family

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonThor.html
- **Summary:** This topic describes power and performance management features of the NVIDIA ® Jetson™ Thor™ product family. It describes the power, thermal, and electrical management features visible to software, as well as some tools and related techniques. NVIDIA Jetson Board Support Packages (BSP) provide many features related to power management, thermal management, and electrical management. These features deliver the best user experience possible…
- **Sections:** Interacting Features #; Kernel Space Power Saving Features #; Chipset Power States #; General Clock Management #; Common Clock Framework #; BPMP Clock DebugFS #; General Regulator Management #; System Power Measurement #

#### Software Packages and the Update Mechanism

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/SoftwarePackagesAndTheUpdateMechanism.html
- **Summary:** NVIDIA provides additional NVIDIA ® Jetson™ Linux software components and updates in APT (Debian) repositories, accessible through the apt utility. These packages are only verified with the root filesystem shipped in this L4T BSP release.
- **Sections:** Installing Additional Packages #; Repackaging Debian Packages #; Building Kernel Debian Packages Yourself #; Using the Repackager Tool #; Converting a Debian File #; Converting Multiple Debian Files #; Converting all Debian Files Under BSP #; Converting a Subset of Files and Placing the Output in the Designated Directory #

#### Test Plan and Validation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/TestPlanValidation.html
- **Summary:** This section provides information about the Flash and Boot test cases. Power on the carrier board and hold the Recovery button.
- **Sections:** Flash and Boot #; Check the Flash and Boot Using the flash.sh Script #; Check the Flash and Boot SDKM #; NVME Boot #; NFS Boot #; System Software #; Detection of USB Hub (FS/HS/SS) #; Detection of USB-3.0 Flashdrive (Hot plug-in) #

#### Working With Sources

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/WorkingWithSources.html
- **Summary:** You can now sync sources that are related to Jetson Linux from the NVIDIA Git server and download the sources from the Jetson Linux page. To sync the sources from the Git server, select one of the following options: Use git clone to clone individual git repositories locally. Check the following table for the URLs of the repositories.

### Other software topics

#### CUDA Instrumentation Methods

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/CUDA.html
- **Summary:** Beginning with the CUDA 12.9 release, the CUDA driver introduces lightweight instrumentation methodologies designed for debugging and development when standard developer tools are not suitable. This user guide provides CUDA developers with an understanding of these instrumentation methods and their applications for debugging on Jetson platforms. These are lightweight instrumentation methods that aim to make debugging any CUDA issue in the…
- **Sections:** Prerequisites #; GPU Task Tracker #; When to Use #; How to Use #

#### Emulation Flash Configurations

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/EmulationSupport.html
- **Summary:** The Jetson AGX Orin Developer Kit can be used to emulate the performance of Jetson AGX Orin 32GB, Jetson AGX Orin 64GB, Jetson Orin NX 16GB, and Jetson Orin NX 8GB production modules. Emulation support helps to significantly reduce the time to market by kick starting development for any Jetson Orin production module on the Jetson AGX Orin Developer Kit. During emulation, the GPU, CPU, and other hardware accelerators are configured according…

#### Multi-Instance GPU (MIG)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/MiG.html
- **Summary:** NVIDIA ® Jetson™ Linux supports Multi-Instance GPU (MIG), which partitions GPU resources so that multiple workloads can run concurrently with hardware-level isolation. Use MIG when you need dedicated GPU slices for separate applications or tenants on a single Jetson device. This page describes MIG support on Jetson platforms and how to configure and use it with this release of Jetson Linux.
- **Sections:** Related Documentation #; Getting Started with MIG on Jetson Thor #; Prerequisite #; Enable MIG Mode #; Query Available Profiles #; Create MIG Instances #; Verify MIG Instances #; Run Graphics on the MIG Graphics Partition #

## Hardware references (9)

### Configuring the Jetson Expansion Headers

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/ConfiguringTheJetsonExpansionHeaders.html
- **Summary:** Each Jetson developer kit includes several expansion headers and connectors (collectively, “headers”): 40‑pin expansion header: Lets you connect a Jetson developer kit to off-the-shelf Raspberry Pi HATs (Hardware Attached on Top) such as Seeed Grove modules, SparkFun Qwiic products, and others. Many of the pins can be used either as GPIO or as “special function I/O” (SFIO) such as I2C, I2S, etc.
- **Sections:** Running Jetson-IO #; Main Screen: Selecting a Header #; Header Screen #; Compatible Hardware Screen #; Configuring 40-Pin Expansion Header #; Configuring the CSI Connector #; Main Screen: Save #; Command Line Interface #

### Controller Area Network (CAN)

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/ControllerAreaNetworkCan.html
- **Summary:** Applies to: Jetson Thor, Jetson AGX Orin, Jetson Orin NX, and Jetson Orin Nano product families. This topic describes the Time Triggered CAN (TTCAN) controller of the NVIDIA ® SoC, and how to use it in user space.
- **Sections:** Important Features #; Jetson Platform Details #; How to Enable CAN #; Kernel DTB #; Pinmux #; Load the CAN Kernel Drivers #; Manage the Network #; Set the interface properties #

### Jetson Developer Kit Setup

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonDeveloperKitSetup.html
- **Summary:** Jetson developer kits are ideal for hands-on AI and robotics learning. Detailed instructions on initial setup through advanced tutorials are available online. The Jetson developer community is ready to help! Getting Started with your Jetson Developer Kit at https://developer.nvidia.com/embedded/learn/getting-started-jetson .

### Jetson EEPROM Layout

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonEepromLayout.html
- **Summary:** This topic describes the layout of EEPROM for NVIDIA ® Jetson™ devices supported by this release of NVIDIA ® Jetson™ Linux. All numeric values are little-endian, i.e. the low-addressed byte contains the least significant digit and the high-addressed byte contains the most significant digit.
- **Sections:** Configuration of Vendor-Specified MAC Addresses #; Value of the CRC-8 Byte #

### Jetson Module Adaptation and Bring-Up

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp.html
- **Summary:** This topic is for users who are developing production software for a Jetson module. It describes how to port Jetson Linux and the U-Boot boot loader from a Jetson developer kit to another hardware platform. A checklist of recommended steps in the hardware bring-up process.

### Jetson Module Adaptation and Bring-Up: Checklists

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/Checklists.html
- **Summary:** This topic presents several checklists of steps in bringing up a custom carrier board with an NVIDIA ® Jetson™ SOM. It presents one group of checklists for hardware, and another for software. The right-hand columns indicate which bring-up steps apply to which processors. An ‘O’ in a given processor’s column indicates a step that applies to that processor; a dash indicates a step that does not.
- **Sections:** Hardware Bring-Up Checklist #; Before Power-On #; Initial Power-On #; Initial Software Flashing #; Power #; Power Optimization #; USB 2.0 PHY #; USB 3.0 #

### Jetson AGX Orin Platform Adaptation and Bring-Up

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/JetsonAgxOrinSeries.html
- **Summary:** This guide describes how to port the Jetson Linux Driver Package (L4T) from the Jetson AGX Orin Developer Kit to another hardware platform. The examples described include code for the Jetson AGX Orin Developer Kit (P3730). Refer to T234 BCT Deployment Guide for information about customizing the configuration files. The Jetson AGX Orin Developer Kit consists of a P3701 System on Module (SOM) that is connected to a P3737 carrier board. Part…
- **Sections:** Board Configuration #; Board Naming #; Placeholders in the Porting Instructions #; Camera Connector Pin Differences #; Root Filesystem Configuration #; MB1 Configuration Changes #; Pinmux Changes #; Identifying the GPIO Number #

### Jetson Orin NX and Nano Series

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/JetsonOrinNxNanoSeries.html
- **Summary:** This guide describes how to port and bring up custom platforms using the NVIDIA® Jetson™ Orin™ NX and Nano modules using the NVIDIA Jetson Linux Driver Package. The examples in this document include code for the Jetson Orin NX and Nano modules connected to the Jetson Orin™ Nano carrier board. Refer to T234 BCT (Boot configuration Table) Deployment Guide for information about customizing the configuration files.
- **Sections:** Board Configuration #; Naming the Board #; Placeholders in the Porting Instructions #; Root Filesystem Configuration #; MB1 Configuration Changes #; Generating the Pinmux dtsi Files #; Changing the Pinmux #; Identifying the GPIO Number #

### Jetson Thor Adaptation and Bring-Up

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/HR/JetsonModuleAdaptationAndBringUp/JetsonThorAdaptationBringUp.html
- **Summary:** This guide describes how to port and bring up custom platforms using the NVIDIA® Jetson™ T5000 module, based on the NVIDIA Jetson Linux Driver Package. The examples in this document include code for the Jetson T5000 module and the Jetson Thor carrier board.
- **Sections:** Board Configuration #; Name the Board #; Placeholders in the Porting Instructions #; Root Filesystem Configuration #; MB1 Configuration Changes #; Generate the Pinmux dtsi Files #; Identify and Use GPIO Pins #; MB2 Configuration Changes #

## Applications and tools (8)

### Board Automation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/BoardAutomation.html
- **Summary:** The carrier boards of the following NVIDIA developer kits provide interfaces for board automation and UART debug output: NVIDIA Jetson AGX Thor Developer Kit includes a USB-C port.
- **Sections:** Host System Setup #; Basic Board Control #; For Jetson AGX Thor #; For Jetson AGX Orin #; For Jetson Orin Nano #; UART Access #

### How to Submit a Bug Report

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/HowToSubmitABugReport.html
- **Summary:** If you encounter an apparent bug in NVIDIA ® Jetson™ Linux or its documentation, you can submit a bug report. $ export DISPLAY=:0 $ xhost +si:localuser:root $ sudo ./nvidia-bug-report-tegra.sh The nvidia-bug-report-jetson.sh script collects logs and other information that you can include in a detailed bug report and writes them to a .log file in the current directory. Based on the installation type, it can also invoke the Graphics…

### Jetson Linux Development Tools

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools.html
- **Summary:** This topic discusses development tools that are included in the NVIDIA ® Jetson™ Linux Basic Support Package (BSP).

### Debugging on Jetson Platforms

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools/DebuggingOnJetsonPlatforms.html
- **Summary:** Jetson devices support debugging tools that allow Jetson application developers to put the processor into known states and trace its behavior while running. Use these tools to debug software you have developed using NVIDIA Jetson Board Support Package (BSP). The Jetson architecture’s debugging support provides:
- **Sections:** CoreSight Trace Support #; Coresight ETE and TRBE #; System Trace Macrocell (STM) #; High Speed Serial Trace Port (HSSTP) #

### Performance Monitoring

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools/PerformanceMonitoring.html
- **Summary:** Performance monitoring is a key feature of Jetson devices. This topic describes the performance monitoring features of Jetson devices. Several functional units are outside the cores. These units are collectively referred to as the uncore . Some of them report uncore performance events and event counters, which are not counted by the core performance counters of the core’s Performance Monitor Unit (PMU).
- **Sections:** Uncore: Performance Monitoring Unit #

### Tegra Combined UART

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools/TegraCombinedUART.html
- **Summary:** The Tegra Combined UART (TCU) is a system that multiplexes debug information from the processors in the CCPLEX cluster with information from other processors. The multiplexing is accomplished in the Sensor Processing Engine (SPE) for NVIDIA ® Jetson™ Orin and the UART Trace Controller (UTC) for NVIDIA ® Jetson™ Thor. It involves all of the processors that supply information. The nv_tcu_demuxer utility runs on a host system and demultiplexes…
- **Sections:** nv_tcu_demuxer Utility #; Examples #; UART Trace Controller (UTC) Technical Details for Jetson Thor #; Key Differences from Jetson Orin #; UTC Architecture #; Client Mapping for Thor #; UTC Configuration #; Advanced Usage for Jetson Thor #

### Tegrastats Utility

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxDevelopmentTools/TegrastatsUtility.html
- **Summary:** The tegrastats utility reports memory usage and processor usage for NVIDIA ® Jetson™ -based devices. You can find the utility in your package at <top>/core/utils/tegrastats .
- **Sections:** Reported Statistics #; Running tegrastats #; To run tegrastats #; To stop tegrastats #; Re-Deploying tegrastats #; To re-deploy tegrastats #; tegrastats Command Line Options #

### Jetson Linux Toolchain

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/AT/JetsonLinuxToolchain.html
- **Summary:** NVIDIA ® specifies the Crosstool-NG gcc 13.2.0 aarch64 toolchain for the following options: Cross-compiling applications to run on this release of NVIDIA ® Jetson™ Linux.
- **Sections:** Toolchain Information #; Downloading the Toolchain #; Extracting the Toolchain #; Setting the CROSS_COMPILE Environment Variable #

## Reference material (3)

### Legal Information

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/RM/LegalInformation.html
- **Summary:** This document is provided for information purposes only and shall not be regarded as a warranty of a certain functionality, condition, or quality of a product. NVIDIA Corporation (“NVIDIA”) makes no representations or warranties, expressed or implied, as to the accuracy or completeness of the information contained in this document and assumes no responsibility for any errors contained herein. NVIDIA shall have no liability for the…

### Package Manifest

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/RM/PackageManifest.html
- **Summary:** NVIDIA ® Jetson™ Linux is provided in the tar file: where <version> is the version of the package for the current release.
- **Sections:** Bootloader #; Kernel #; Kernel Supplements TBZ2 #; Kernel Headers TBZ2 #; Tools #; NV Tegra #; Config TBZ2 #; Graphics Demos #

### Related Documentation

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/RM/RelatedDocumentation.html
- **Summary:** Many documents related to NVIDIA ® Jetson™ Linux are available from: The Jetson home page of the NVIDIA Developer web site
- **Sections:** Application Notes and Other Documents #; READMEs #

## index.html (1)

### Welcome

- **URL:** https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/index.html
- **Summary:** This Developer Guide applies to NVIDIA ® Jetson™ Linux version 39.2 GA , which supports both the Jetson Thor and Jetson Orin product families. NVIDIA Jetson is the world’s leading platform for AI at the edge. Its high-performance, low-power computing for deep learning , and computer vision makes Jetson the ideal platform for compute-intensive projects. The Jetson platform includes a variety of Jetson modules with NVIDIA JetPack™ SDK.
- **Sections:** Jetson Developer Kits and Modules #; Software for Jetson Modules and Developer Kits #; Documentation for Jetson Modules and Developer Kits #; Devices Supported by This Document #; How Developer Guide Topics Identify Devices #

