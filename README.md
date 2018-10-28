# Archived code for 2016 Libelium Waspmote PRO v1.2 with Gas Sensor Board v2.0 and LoRaWAN

This is just an archive of an Arduino sketch (and its required development tools), used to get more details from a
Libelium Waspmote "Plug & Sense!" Smart Environment device as used by the City of Haarlem from May 2016 until
October 2017.

## Contents

- [Code quality](#code-quality)
- [Sensor quality](#sensor-quality)
- [Hardware configuration](#hardware-configuration)
- [Project contents](#project-contents)
- [LoRaWAN](#lorawan)
  - [Registering with The Things Network](#registering-with-the-things-network)
  - [Uplink payload format](#uplink-payload-format)
  - [TTN Payload function](#ttn-payload-function)
  - [RN2483 known issues](#rn2483-known-issues)
- [Programming using the Waspmote PRO IDE v04](#programming-using-the-waspmote-pro-ide-v04)
  - [Installing the correct IDE](#installing-the-correct-ide)
  - [Documentation errors](#documentation-errors)
  - [Enabling debug logging](#enabling-debug-logging)
  - [Using the LEDs](#using-the-leds)
  - [Waspmote IDE known issues](#waspmote-ide-known-issues)


## Code quality

This is by no means intended to be production-ready software. Things that come to mind:

- No power optimization has been done, at all. Like maybe the main board can sleep while the sensor board is awaiting
  the initialization of a sensor? Maybe one can take measurements from one sensor while another is already initializing?
  Note that the documentation states:

  > Given that the current allowed in the digital switches’ output is limited (about 200mA), it is recommended to not
  > overload them by activating a number of sensors at the same time which in total may surpass this current.

- The used LoRaWAN packet format allows for ridiculously accurate temperature readings, and for negative values for
  atmospheric pressure and NO<sub>2</sub>. All this will/should not happen, and hence is not quite efficient.

- Only use the LED for the first few measurements after a restart.

- Only take measurements when the battery level is good.

- Allow for remote configuration, using downlinks. (Store remote settings in non-volatile memory to survive restarts.)

- Allow for remotely restarting the device to join another LoRaWAN network.

- Calculate the measurement interval based on the start of measurements, rather than time between measurements.

- Confirm that the retry-until-success in the `setLoRaWAN` helper functions does not cause problems.

Be sure to read the full documentation as provided by Libelium; this sketch was merely based on examples without diving
into the technical documentation too much.


## Sensor quality

Two of these devices were used in the field from May 2016 until October 2017. Their hardware was already outdated when
first installed, and never gave us any reliable results. One unit broke down due to external factors, and the other was
taken into the office to see if its output could be improved by using different settings, but to no avail.

The source code as used in the field was never released by an intermediate supplier. But peeking into its serial output
revealed that for each sensor it was taking 10 samples, each 1 second apart, after which only the mean (average) value
was transmitted. But the serial output also proved that the actual samples often showed a large variation. Rather than
the mean, this sketch determines the median to discard the outliers, and also sends the minimum and maximum values for
analysis. But as even temperature measurements would often show large variations within only 10 seconds, the device was
declared crap and this sketch has never been used in the field.

So, I do not endorse the early 2016 device, as measurements for our two test devices were really bad. Later models may
be okay, but I have not used those. The control hardware is quite nice, with great support for deep sleep and watchdog
timers, and even offering a real-time clock. So if the sensors have meanwhile improved, and when not using generated
code, then this might be a nice unit.

In March 2017, Smart Environment (which is the Plug & Sense! version for the Gases sensor board) was discontinued, in
favor of Smart Environment PRO (Gases PRO) and Smart Cities PRO, both of which were already available when our supplier
got us the old version instead. Browsing recent documentation surely makes them look much better.

:warning: Note that the reported NO<sub>2</sub> values are just voltages. When calibration parameters are known, one
could use `SensorGasv20.calculateResistance` and `SensorGasv20.calculateConcentration` to get a PPM value. Next, that
value should also be compensated for temperature and atmospheric pressure (which is exactly why this combination of
sensors was selected). This sketch simply transmits the voltage values without any such postprocessing.


## Hardware configuration

Socket configuration for this sketch:

- A: temperature, 9203, MCP9700A
- B: atmospheric pressure, 9250, MPX4115A
- D: NO<sub>2</sub> 9238-Pb, MiCS-2714; https://www.libelium.com/forum/viewtopic.php?f=28&t=22007&p=63548#p63568

The LoRaWAN module identified itself as `RN2483 1.0.1 Dec 15 2015 09:38:09`.

The NO<sub>2</sub> sensor needs some parameters to be set, typically through some calibration. Without calibration,
neither the documentation nor the support forum are helpful:

- Gain: depends on the concentrations to be measured; changing the gain keeps the sensor from getting saturated.

  > As a general rule, gain will be fixed at 1 in almost every application, only in very specific situations, such as
  > operation in the limits of the sensor range, it will be necessary a different value.

- Load resistance: depends on the actual calibration.

  > Recommended values of load resistor: NO2 20 KOhm typical to 100K

Also, the NO<sub>2</sub> sensor needs to be pre-heated for at least 30 seconds.


## Project contents

 - [src/WaspmoteOTAA](./src/WaspmoteOTAA): the actual sketch and its dependencies.

 - [src/generated](./src/generated): the sketch as generated by a Libelium tool, given the sensor configuration. As the
   tool did not support LoRaWAN, and the code yields a very verbose text-based payload, this is only included as
   documentation.

 - [tools](./tools): the legacy Libelium Waspmote PRO IDE for Windows and OS X/macOS, and USB drivers.

 - [docs](./docs): some legacy Libelium documentation, valid for this configuration.


## LoRaWAN

### Registering with The Things Network

To register the device with The Things Network:

- Use the Waspmote PRO IDE to upload the sketch, and peek into the serial output to see its hardware Device EUI.

- Go to https://console.thethingsnetwork.org

- Register an application. This will get you a public AppEUI.

- Register a new OTAA device to the application, using the device's EUI. This will get you a device-specific AppKey.

- Copy the application's public AppEUI and the device's secret AppKey into the sketch.

- Upload the updated sketch.

### Uplink payload format

The values are sent in a 19 bytes MSB format. All values, except the battery level, are 16 bits signed integers where
their original float value has been multiplied by 100 to retain 2 decimals.

| bytes | data
| :---: | ----------------------------------------------------------------------------
|  1-6  | 3 × 16 bits minimum, median and maximum values for temperature, Celcius
|  7-12 | 3 × 16 bits minimum, median and maximum values for atmospheric pressure, kPa
| 13-18 | 3 × 16 bits minimum, median and maximum values for NO<sub>2</sub>, Volt
|   19  | 8 bits unsigned battery level, percentage

This is not at all optimal:

- The decimals in the temperature readings are probably not very accurate and can be discarded, maybe allowing one
  to limit temperature readings to use 3 × 8 bits.

- Atmospheric pressure [should be](https://en.wikipedia.org/wiki/List_of_atmospheric_pressure_records_in_Europe) in
  the range of 87.0 to 109.0, hence a variation of only 22 kPa. With one decimal and an offset of 85 this would
  easily fit in a single byte.

- Providing hPa rather than kPa seems to be more common.

- Readings for pressure and NO<sub>2</sub> can, if all is well, not be negative.

- After determining that the readings are okay, one should stop sending the minimum and maximum values.

### TTN Payload function

To decode the values back into their original values:

```javascript
function Decoder(bytes, port) {
  var i = 0;

  function nextFloat() {
    // Sign-extend to 32 bits to support negative values, by shifting 24 bits
    // (too far) to the left, followed by a sign-propagating right shift:
    return (bytes[i++]<<24>>16 | bytes[i++]) / 100;
  }

  function nextMinMedianMax() {
    return {
      min: nextFloat(),
      median: nextFloat(),
      max: nextFloat()
    }
  }

  return {
    temperature: nextMinMedianMax(),
    pressure: nextMinMedianMax(),
    no2: nextMinMedianMax(),
    battery: bytes[i++]
  }
}
```

### RN2483 known issues

- After a factory reset, make sure to set (dummy) values for DevAddr, AppSKey and NwkSKey, for otherwise calling
  `LoRaWAN.saveConfig` (actually `mac save`) does not save the OTAA settings, and/or `LoRaWAN.joinABP` does not
  recognize that they were saved.

- Limited tests show that joining on low data rates might be troublesome, and that ADR might not be working. This has
  not been investigated.


## Programming using the Waspmote PRO IDE v04

### Installing the correct IDE

This device needs the old API, version 023, which is not included in the latest Waspmote PRO IDE. One could manually
install it, but that's probably not worth the effort. The old IDE also does not support C++11 out of the box (while
the latest IDE does), but even though that adds support for lambdas which would be a nice replacement of the function
pointers used in `_execLoRaWAN` now, that's probably not worth the effort either.

So, use the December 2013 Waspmote PRO IDE v04, as available on http://www.libelium.com/v12/development/ and in the
[tools](./tools) folder.

Beware that Libelium warns one should never replace its proprietary bootloader, so beware when using different tooling:

> The microcontroller Flash (128KB) contains both the uploaded program and the bootloader. The bootloader is a small
> program which is executed at the beginning and proceeds to run the uploaded program. Libelium provides the Waspmote
> IDE which won’t permit rewriting the bootloader.
>
> Do **NOT** use other IDEs, **only** the Waspmote IDE is recommended.
>
> Libelium does not recommend to implement Watchdog timers as some users have had some problems and the microcontroller
> has needed to be re-flashed.
>
> If the bootloader is overwritten by using any of the previous practices, the warranty will be voided.

### Documentation errors

- "Board configuration and programming" in "gases-sensor-board-2.0.pdf" suggests that it suffices to configure the
  sensors in the `setup()` method. This is true when not powering off the sensor board, and the very example does
  indeed not power off that board when invoking `PWR.deepSleep`. However, when using true deep sleep, then the sensor
  board _is_ switched off, and needs to be re-configured after waking up. As the `setup()` method is not invoked after
  waking from deep sleep, the configuration needs to be done in `loop()`, as "waspmote-programming-guide.pdf" claims:

  > #### Gases Board 2.0
  > Remember that when turning off the board the configuration of the sensor stages will be lost.

- Most examples do not enable the RTC, and peeking into the `WaspSensorGas_v20` library code seems to suggest that
  the RTC is enabled if needed, but "Board configuration and programming" in "gases-sensor-board-2.0.pdf" states:

  > Turn on the RTC to avoid possible conflicts in the I2C bus.

### Enabling debug logging

Even when enabling debugging, the Waspmote UART library hides most of the responses as soon as it finds a match. Like
to see the actual RN2483 version information, enabling debugging does not help. Instead, one needs:

```cpp
uint8_t result = LoRaWAN.sendCommand("sys get ver\r\n", "\r\n", "invalid_param");
```

...which tells the `WaspUART` superclass to send `sys get ver` and then wait for either a newline (as returned after the
RN2483 has printed its version details) or for the `invalid_param` error.

To enable debugging see the header files in the IDE's `hardware/waspmote/cores/waspmote-api` folder, specifically the
file `WaspUART.h` for debugging of its derived `WaspLoRaWAN`.

### Using the LEDs

The Waspmote being installed in a Plug & Sense! product, the red LED in its power button is actually addressed using
`Utils.blinkGreenLED`, not using `Utils.externalLEDBlink`.

### Waspmote IDE known issues

- Folder names cannot include dashes.

- On OS X and macOS, the old IDE needs the legacy Java SE 6 runtime; OS X and macOS will prompt one to download from
  https://support.apple.com/kb/DL1572 However, though the names of the downloads are always `javaforosx.dmg`, an old
  2017 download from that very URL will not work for macOS 10.14 Mojava. After upgrading macOS make sure to download a
  more recent release from the same URL.

- Using the ancient Java, one will see errors like the following, but all works fine:

  > Exception in thread "AWT-EventQueue-0" java.lang.RuntimeException: Non-Java exception raised, not handled!
  > (Original problem: Deprecated in 10_12... DO NOT EVER USE CGSEventRecord directly. Bad things, man.... bad things.)
