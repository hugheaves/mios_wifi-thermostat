mios_wifi-thermostat
====================

![Picture of 3M-50 Thermostat](https://github.com/hugheaves/mios_wifi-thermostat/raw/master/resources/thermostat.jpg)
![Screenshot of Vera Thermostat Control for 3M-50](https://github.com/hugheaves/mios_wifi-thermostat/raw/master/resources/VeraControl.png)

Table of Contents
=================

[Introduction](#introduction)  
[Requirements](#requirements)  
[What's New / Version History](#whats-new--version-history)  
[Installation](#installation)  
[Operation](#operation)  
[Advanced Configuration](#advanced-configuration)  
[Known Issues / Limitations](#known-issues--limitations)  
[Planned Enhancements](#planned-enhancements)  
[Enhancement "Ideas"](#enhancement-ideas)  

## Introduction

The [Radio Thermostat Wi-Fi Plugin](https://apps.mios.com/plugin.php?id=1618) integrates Radio Thermostat products using the USNAP Wi-Fi module with Vera. (i.e. the [Filtrete 3M-50](http://www.radiothermostat.com/filtrete/products/3M-50) available at [Home Depot](http://www.homedepot.com/buy/electrical-home-automation-security-home-automation-climate-control/filtrete-7-day-touchscreen-wifi-enabled-programmable-thermostat-with-backlight-182800.html))  The plugin is designed to co-exist with existing thermostat controls, including Radio Thermostat's cloud, and manual control from the physical thermostat interface.

## Requirements

* A Vera device with UI5
* A compatible Radio Thermostat Wi-Fi thermostat. This plug-in was developed and tested with the [3M-50](http://www.radiothermostat.com/filtrete/products/3M-50), but should work with other Radio Thermostat  thermostats with the Wi-Fi USNAP module.
* Your thermostat must already be provisioned and connected to your LAN. (I suggest going through the normal provisioning process to connect your thermostat to the Radio Thermostat cloud - this will also make sure you have the latest firmware)
* You need to know the IP address of your thermostat. I suggest either assigning a static IP to the thermostat, or creating a static / permanent DHCP allocation for the thermostat in your router.
* The thermostat firmware must be version 1.04.64 or newer. *Note: to be able to use the full feature set of the plugin, firmware version 1.04.82 or newer is required.* To check your current thermostat version, browse to http://IPAddressOfYourThermostat/ and look for "Firmware Version" at the bottom of the page.

## What's New / Version History

This is a list of the changes, bug fixes, and new features in each released version of the plugin.

### 3.0 - Released 2/14/2013
* Fixed bug with energy LED controls.

### 2.7 - Unreleased
* Minor changes to solve issue with deployment.

### 2.6 - Unreleased
* Minor changes to solve issue with deployment.

### 2.5 - Released 1/3/2013
* Bug fix: Fixed inability to add notifications
* Added the ability to turn on "energy LED's" from the UI

### 2.1 - Released 6/20/2012
* Bug fix: Fixed failure to correctly initialize newly added thermostat devices

### 2.0 - Released 6/14/2012
* Changed UPnP device type of the plugin to "urn:schemas-hugheaves-com:device:HVAC_ZoneThermostat:1" to prevent user interface problems for installations with both Z-Wave thermostats and RTCOA Wifi thermostats.
* Added the "CreateGenericDevice" option. When enabled, this creates an additional device of type "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1" controlling the same physical thermostat as the main device. This allows the plugin to maintain compatibility with apps that only recognize "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1" as thermostats.

### 1.0 - Released 5/16/2012
* Added "LooseTempControl" setting
* Fixed minor bug with hold status updates

### 0.9 - Released 5/14/2012
* Added "custom" thermostat icon (looks like a mini 3M-50)
* Added GPL license headers to source code
* Code cleanup / refactoring

### 0.8 - Released 4/23/2012
* Added clock sync function to synchronize the thermostat's clock with Vera's clock. 
* Added UPnP API functions to control LED's and PMA (Price Messaging Area). The PMA is the (mostly unused) numerical display in the upper left corner of the 3M-50.
* Added remote temperature function - allows any Vera supported temperature device to replace the internal temperature sensor in the thermostat
* Added PMA temperature function - displays the current temperature from any Vera supported temperature device in the PMA (Price Messaging Area). 
* Added "Program Setpoint" feature - this feature updates the built-in program in the thermostat to maintain the new current setpoint everytime the setpoint is changed. This helps keep th


### 0.7 - Released 3/19/2012
* Added adjustable polling interval
* Added Celsius support
* Re-based UI on current UI5 Z-Wave thermostat UI
* Added support for maintaining hold setting across mode changes
* Added support for "Force Hold" to always keep thermostat in hold mode
* Reworked logging code to support run-time adjustable log levels

### 0.4 - Released 2/17/2012
* Improved reliability of communications, minor bug fixes

### 0.1 - Released 2/15/2012
* Initial release

## Installation

This is (currently) a UI5 only plugin, so the easiest way to install the plug-in is via the [Vera Web Portal](http://docs5.mios.com/doc.php?page=mymios_web_portal):

1. In your Vera Web Portal, navigate to "Apps" -> "Install Apps", and then search for "Thermostat" to find the "Radio Thermostat Wifi plugin"
2. Click on "Install" to install the plugin.
3. Vera will display the message "Please wait while the plugin is downloaded". 

![Screenshot showing please wait dialog](https://github.com/hugheaves/mios_wifi-thermostat/raw/master/resources/Please%20Wait.png)

4. Once the plugin has been downloaded and installed, Vera will show the device configuration dialog
5. Click on the "Advanced" tab of the device configuration dialog, enter the IP Address of your thermostat in the "ip" field.

![Screenshot showing advanced configurtation tab](https://github.com/hugheaves/mios_wifi-thermostat/raw/master/resources/Advanced%20Tab.jpg)

6. Close the configuration dialog, and click "Save" to save your configuration.
7. In a minute or two, your thermostat device will appear in your device list.

# Operation

Thermostat control changes (mode, temp settings, etc.) made in the Vera UI are applied immediately to the thermostat. By default, the plugin also polls the thermostat every 60 seconds and will update any temperature, operating mode, set points, and fan state changes made from other places (Radio thermostat cloud, manual changes on the stat, smart phone apps, etc.)

Vera does not attempt to take exclusive control of the thermostat. Unless the thermostat is placed in "Hold" or "Simple Screen" mode, the schedule programmed into the thermostat will still be in effect. If you're feeling adventurous and want to completely control the thermostat from Vera, I would suggest placing the thermostat in Simple Screen mode. (this is effectively hold mode, but without displaying "Hold" on the thermostat display) See the "How to change from standard screen to simple screen" link on [this page](http://www.radiothermostat.com/filtrete/help/) for information on how to change to simple screen mode.

## Advanced Configuration

The following settings on the "Advanced" tab of the device configuration dialog can be used to alter the default behavior of the thermostat plug-in.

### InitialPollDelay
*Required Plugin Version:* 0.7+  
*Default Value:* 3  
*Description:* The time period (in seconds) to wait between the device being initialized by Vera (i.e. at Vera startup) and the first poll of the thermostat device. If you have multiple thermostats, this setting can be used to "stagger" polling so that not all thermostats are polled at the same time. 

### PollInterval
*Required Plugin Version:* 0.7+  
*Default Value:* 60  
*Description:* The time period (in seconds) to wait between each poll of the thermostat.

### LogLevel
*Required Plugin Version:* 0.7+  
*Default Value:* 20  
*Description:* Set the logging level / verbosity. Three levels are supported:
* 10 - Error (least verbose)
* 20 - Info (medium verbosity)
* 30 - Debug (most verbose)

### ForceHold
*Required Plugin Version:* 0.7+  
*Default Value:* 0  
*Description:* When this variable is set to "1", the thermostat plugin will set the thermostat into "hold" mode and restore the previous setpoint anytime it discovers that the thermostat is not in "hold" mode. If you are using Vera to control your thermostat schedule, this setting is useful to prevent the thermostat being accidentally removed from hold mode and the internal thermostat program "taking over".

### ProgramSetpoints
*Required Plugin Version:* 0.8+  
*Default Value:* 0  
*Description:* When this variable is set to "1", the plugin reprograms (i.e. overwrites) the thermostat's built-in schedule with a schedule that maintains the current set point indefinitely. Every time the current setpoint is changed either from Vera or the thermostat, the plugin will reprogram a "hold schedule" into the thermostat to hold the new temperature setpoint. The idea behind this feature is to prevent the "battle of the schedules" that occurs if Vera is controlling the schedule of the thermostat, but the thermostat is accidentally removed from "hold mode" (hold mode disables the built in schedule). This provides another way (other than Force Hold) to prevent the thermostat's internal schedule from causing problems.

Note: Due to the fact that this feature erases the internal schedule of your thermostat, I suggest using "ForceHold" by first, and then enabling this feature only if "ForceHold" doesn't provide enough control of the thermostat.

### ClockSync
*Required Plugin Version:* 0.8+  
*Default Value:* 0  
*Description:* When this variable is set to "1", the thermostat plugin will synchronize the thermostats internal clock with Vera's clock. Even though there is no way to set the seconds value on the thermostat clock, this feature uses some fancy "timing trickery" to set the thermostat clock to within a second or two of Vera's clock.

Note: if you're using Radio Thermostat's cloud services, I wouldn't suggest enabling this feature as the plugin will "fight" with the cloud to keep your clock in sync.

### PMATempDevice
*Required Plugin Version:* 0.8+  
*Default Value:* 0  
*Description:* If you set this variable to the Vera device ### (_not_ the Z-Wave ID - see below screenshot) of a Vera supported temperature sensor, then the temperature sensor of that device will be displayed in the Price Messaging Area of the thermostat. (On the 3M-50, the PMA is the numeric display area in the upper left hand corner of the thermostat).

Note that the temperature sensor doesn't necessarily have to be a physical device. For example, the [Weather Plugin](http://code.mios.com/trac/mios_weather) provides a virtual temperature sensor that display the current outside temperature as read from Google's weather service. This temperature can be displayed on your thermostat to give an "at a glance" outside temperature reading even if you don't have a real outside temperature sensor. (Cool, huh? :)

![Screenshot showing how to identify device number](https://github.com/hugheaves/mios_wifi-thermostat/raw/master/resources/DeviceNum.png)

### RemoteTempDevice
*Required Plugin Version:* 0.8+  
*Default Value:* 0  
*Description:* This variable works the same way as !PMATempDevice, except that the Vera temperature device temperature is displayed as the main temperature on your thermostat, and the entire thermostat operation (heating, cooling, schedule activation, etc.) is then based on the temperature of the Vera supported sensor, not the thermostat's internal temperature sensor.

### LooseTempControl
*Required Plugin Version:* 1.0+  
*Default Value:* 0  
*Description:* When this variable is set to "1", the thermostat plugin will not attempt to maintain the Vera setpoint when changing operating mode or hold status. Typically, this means that the thermostat setpoint will revert to setpoint in the thermostat's internal schedule. When the variable is set to "0", the plugin will make sure the thermostat remains at the Vera setpoint even when changing mode or hold status. 

### CreateGenericDevice
*Required Plugin Version:* 2.0+  
*Default Value:* 0  
*Description:* When this variable is set to "1", the thermostat plugin will create an extra "genric" thermostat device of type "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1". Both the main thermostat device and this generic device will control the same physical thermostat. This feature allows the Wifi thermostat to be recognized by applications that only recognize the generic "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1" devices as thermostats. If your Wifi thermostats are controllable in the apps that you use, then there is no need to enable this feature.

## Known Issues / Limitations

* In releases 0.7 and older, changing the temperature set point for heating will place the thermostat in heating mode, regardless of it's current mode. (i.e. the thermostat will switch from cooling to heating mode). The reverse is also true: setting the cooling set point will place the thermostat in cooling mode. This is not a limitation in version 0.8 and newer.

## Planned Enhancements

The current focus is on stabilization and bug fixes. There are no planned enhancements at this time.

## Enhancements "Ideas"

This is a list of things that may be possible to implement in the future. If you're interested in any of these (or others), let me know:
* "Enhanced Status Display" - display current status information (fan running, actively cooling, etc.), not just settings, in the Vera UI. Also, poll thermostat relay states for more detailed status information for multi-stage systems. For example, instead of just "heating", provide a status that differentiates between which stage is active (heat-pump vs aux/electric). This would be useful for detailed energy tracking.
* "Schedule Control" - View and set thermostat's internal schedule from Vera UI (instead of controlling it via Vera)
* "Firmware update notification" - Provide notification when a new firmware update is available
* "Apply firmware update" - Trigger thermostat firmware update from within Vera
