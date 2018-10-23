/**
 * An example sketch for a 2016 Libelium Waspmote PRO v1.2, with Gas Sensor Board v2.0 and RN2483 LoRaWAN for EU868,
 * using API v023.
 *
 * Hardware configuration of sockets:
 *   - A = temperature, 9203, MCP9700A
 *   - B = atmospheric pressure, 9250, MPX4115A
 *   - D = NO2, 9238-Pb, MiCS-2714 -- https://www.libelium.com/forum/viewtopic.php?f=28&t=22007&p=63548#p63568
 *
 * Use of this source code is governed by the MIT license that can be found in the LICENSE file.
 */

#include <WaspSensorGas_v20.h>
#include <WaspLoRaWAN.h>
// The old Arduino/Waspmote IDE does not support project sub-folders for third-party libraries.
#include "RunningMedian.h"

/**
 * LoRaWAN OTAA 64-bit public Application EUI. MSB; a TTN-generated AppEUI always starts with 0x70.
 */
char APP_EUI[] = "7000000000000000";

/**
 * LoRaWAN OTAA 128-bit secret Application Key. MSB.
 */
char APP_KEY[] = "00000000000000000000000000000000";

/**
 * LoRaWAN initial data rate, used for OTAA Join. Low data rates seem troublesome for OTAA; needs investigation.
 *
 *   0: SF = 12, BW = 125 kHz, bitrate = 250 bps
 *   1: SF = 11, BW = 125 kHz, bitrate = 440 bps
 *   2: SF = 10, BW = 125 kHz, bitrate = 980 bps
 *   3: SF = 9, BW = 125 kHz, bitrate = 1760 bps
 *   4: SF = 8, BW = 125 kHz, bitrate = 3125 bps
 *   5: SF = 7, BW = 125 kHz, bitrate = 5470 bps
 */
uint8_t INITIAL_DR = 3;

/**
 * LoRaWAN application port; any value from 1 to 223.
 */
uint8_t PORT = 1;

/**
 * Interval between the completion of one transmission, and the initialization of the next measurement cycle.
 */
char *sleepTime = "00:00:15:00";

/**
 * Number of seconds to wait after powering on the gases board.
 */
uint8_t boardInitSeconds = 2;

/**
 * Number of samples to take for temperature. As the median is taken, an odd number makes most sense.
 */
uint8_t temperatureSampleCount = 9;

/**
 * Number of samples to take for atmospheric pressure. As the median is taken, an odd number makes most sense.
 */
uint8_t pressureSampleCount = 9;

/**
 * Number of samples to take for NO2. As the median is taken, an odd number makes most sense.
 */
uint8_t no2SampleCount = 9;

/**
 * Number of seconds to pre-heat the NO2 sensor. This must be at least 30 seconds.
 */
uint8_t no2InitSeconds = 30;

/**
 * Gain for the NO2 sensor, 1 to 100. This depends on the concentrations to be measured; changing the gain keeps the
 * sensor from getting saturated. As a general rule, gain will be fixed at 1 in almost every application; only in very
 * specific situations, such as operation in the limits of the sensor range, a different value will be necessary.
 */
uint8_t no2Gain = 1;

/**
 * Load resistor for the NO2 sensor, 1 to 100 kOhm. This depends on calibration and is typically 20.
 */
float no2LoadResistor = 20.0;


// ====================================================================================================================
// End of user configuration
// ====================================================================================================================


/**
 * Socket (UART) to which the LoRaWAN module is connected.
 */
uint8_t socket = SOCKET0;

/**
 * Current stage of the script.
 */
uint8_t stage = 1;

/**
 * Buffer to hold the binary LoRaWAN uplink. MSB.
 */
byte data[50];

void flashLed() {
    Utils.blinkGreenLED(25);
}

void blinkLed(uint8_t count) {
    delay(500);
    Utils.blinkGreenLED(200, count);
    delay(500);
}

void blinkLedError(uint8_t count) {
    delay(500);
    Utils.blinkGreenLED(3000);
    Utils.blinkGreenLED(200, count);
    delay(500);
}

void printLoRaWANResult(uint8_t result, char *charResult[] = NULL, uint32_t *intResult = NULL) {
    switch (result) {
        case LORAWAN_ANSWER_OK:
            if (charResult != NULL) {
                USB.println(*charResult);
            } else if (intResult != NULL) {
                USB.println(*intResult);
            } else {
                USB.println(F("OK"));
            }
            break;
        case LORAWAN_ANSWER_ERROR:
            USB.println(F("ANSWER_ERROR - Module communication error / erratic response to a function"));
            break;
        case LORAWAN_NO_ANSWER:
            // includes duty cycle proplems after 3 x OTAA on SF12?
            USB.println(F("NO_ANSWER - Module didn't respond"));
            break;
        case LORAWAN_INIT_ERROR:
            USB.println(F("INIT_ERROR - Required keys to join to a network were not initialized (ABP)"));
            break;
        case LORAWAN_LENGTH_ERROR:
            USB.println(F("LENGTH_ERROR - Error with data length / data to be sent length limit exceeded"));
            break;
        case LORAWAN_SENDING_ERROR:
            USB.println(F("SENDING_ERROR - Sending error / server did not respond"));
            break;
        case LORAWAN_NOT_JOINED:
            USB.println(F("NOT_JOINED - Module hasn't joined a network"));
            break;
        case LORAWAN_INPUT_ERROR:
            USB.println(F("INPUT_ERROR - Invalid parameter"));
            break;
        case LORAWAN_VERSION_ERROR:
            USB.println(F("VERSION_ERROR - Invalid version"));
            break;
        default:
            USB.print(F("ERROR "));
            USB.println(result, DEC);
    }
}

/**
 * Executes a function from the WaspLoRaWAN class, and repeats if unsuccessful.
 */
void _execLoRaWAN(const __FlashStringHelper *msg,
                  char *charResult[] = NULL, uint32_t *intResult = NULL,
                  uint8_t(WaspLoRaWAN::*f)() = NULL,
                  uint8_t(WaspLoRaWAN::*g)(char *) = NULL, char *c = 0,
                  uint8_t(WaspLoRaWAN::*h)(uint8_t) = NULL, uint8_t i = 0) {

    // loop until result is LORAWAN_ANSWER_OK
    while (1) {
        USB.print(msg);
        uint8_t result;
        if (f) {
            result = (LoRaWAN.*f)();
        } else if (g) {
            result = (LoRaWAN.*g)(c);
        } else {
            result = (LoRaWAN.*h)(i);
        }

        USB.print(F(": "));
        printLoRaWANResult(result, charResult, intResult);
        if (result == LORAWAN_ANSWER_OK) {
            break;
        }

        // As we're using blinkLed(stage++), the current value for stage is one too high:
        blinkLedError(stage - 1);
        if (result != LORAWAN_ANSWER_ERROR) {
            // When not resetting, then the module does not seem to recover from LORAWAN_NO_ANSWER. For OTAA during
            // testing only LORAWAN_ANSWER_ERROR (recoverable twice) and LORAWAN_NO_ANSWER occurred.
            LoRaWAN.reset();
        }
    }
}

/**
 * Prints the given message and invokes the given function without any parameters until it returns success, and upon
 * success prints the value of the given reference.
 *
 * @param msg the message to print
 * @param f the function to invoke
 * @param charResult the reference to the char result to print
 */
void getLoRaWAN(const __FlashStringHelper *msg, uint8_t(WaspLoRaWAN::*f)(), char *charResult) {
    _execLoRaWAN(msg, &charResult, NULL, f);
}

/**
 * Prints the given message and invokes the given function without any parameters until it returns success, and upon
 * success prints the value of the given reference.
 *
 * @param msg the message to print
 * @param f the function to invoke
 * @param intResult the reference to the numeric result to print
 */
void getLoRaWAN(const __FlashStringHelper *msg, uint8_t(WaspLoRaWAN::*f)(), uint32_t *intResult) {
    _execLoRaWAN(msg, NULL, intResult, f);
}

/**
 * Prints the given message and invokes the given function without any parameters until it returns success.
 *
 * @param msg the message to print
 * @param f  the function to invoke
 */
void setLoRaWAN(const __FlashStringHelper *msg, uint8_t(WaspLoRaWAN::*f)()) {
    _execLoRaWAN(msg, NULL, NULL, f);
}

/**
 * Prints the given message and invokes the given function with the given char* parameter, until it returns success.
 *
 * @param msg the message to print
 * @param g the function to invoke
 * @param param the parameter to pass to the function
 */
void setLoRaWAN(const __FlashStringHelper *msg, uint8_t(WaspLoRaWAN::*g)(char *), char *param) {
    _execLoRaWAN(msg, NULL, NULL, NULL, g, param);
}

/**
 * Prints the given message and invokes the given function with the given int parameter, until it returns success.
 *
 * @param msg the message to print
 * @param h the function to invoke
 * @param param the parameter to pass to the function
 */
void setLoRaWAN(const __FlashStringHelper *msg, uint8_t(WaspLoRaWAN::*h)(uint8_t), uint8_t param) {
    _execLoRaWAN(msg, NULL, NULL, NULL, NULL, NULL, h, param);
}

void printFloat(const __FlashStringHelper *msg, float f) {
    // USB.printf does not support Flash-strings, nor floats
    USB.print(msg);
    char s[10];
    Utils.float2String(f, s, 2);
    USB.print(s);
}

void printInt(const __FlashStringHelper *msg, int8_t i) {
    USB.print(msg);
    USB.print(i, DEC);
}

void printMemory() {
    USB.printf("  - Free memory: %d bytes\n", freeMemory());
}

void setup() {
    stage = 1;
    blinkLed(stage++);

    USB.ON();
    USB.print(F("Configuring LoRaWAN module "));

    RTC.ON();
    // Small stabilization delay
    delay(100);
    // If one cares for the correct time settings then just uncomment the line below, set some near-future value,
    // upload, restart the device around the expected time, and then upload the same sketch without the next line.
    // Format: [yy:mm:dd:dow:hh:mm:ss] where dow=1 for Sunday, or 7 for Saturday.
    // RTC.setTime("18:10:22:02:19:00:00");
    USB.println(RTC.getTime());
    RTC.OFF();

    setLoRaWAN(F("  - Switch on"), &WaspLoRaWAN::ON, socket);
    setLoRaWAN(F("  - Factory reset"), &WaspLoRaWAN::factoryReset);
    // Print the hardware EUI required to register the device at The Things Network
    getLoRaWAN(F("  - Get hardware EUI"), &WaspLoRaWAN::getEUI, LoRaWAN._eui);

    USB.print(F("  - Get version: "));
    uint8_t result = LoRaWAN.sendCommand("sys get ver\r\n", "\r\n", "invalid_param");
    if (result == 1) {
        USB.print(LoRaWAN._buffer, LoRaWAN._length);
    } else {
        USB.println(F("FAILED"));
    }

    USB.print(F("  - Get Waspmote serial number: "));
    USB.println(Utils.readSerialID());

    // Some dummy values need to be set, for otherwise joinABP after a deep sleep yields error 3, Required keys to join
    // to a network were not initialized.
    setLoRaWAN(F("  - Set dummy DevAdr"), &WaspLoRaWAN::setDeviceAddr, "00000000");
    setLoRaWAN(F("  - Set dummy AppSKey"), &WaspLoRaWAN::setAppSessionKey, "00000000000000000000000000000000");
    setLoRaWAN(F("  - Set dummy NwkSKey"), &WaspLoRaWAN::setNwkSessionKey, "00000000000000000000000000000000");
    // Not specifying a specific DevEUI will use the hardware EUI
    setLoRaWAN(F("  - Set DevEUI to hardware EUI"), &WaspLoRaWAN::setDeviceEUI);
    setLoRaWAN(F("  - Set AppEUI"), &WaspLoRaWAN::setAppEUI, APP_EUI);
    setLoRaWAN(F("  - Set AppKey"), &WaspLoRaWAN::setAppKey, APP_KEY);
    setLoRaWAN(F("  - Set data rate"), &WaspLoRaWAN::setDataRate, INITIAL_DR);
    setLoRaWAN(F("  - Set ADR"), &WaspLoRaWAN::setADR, "on");
    // Save the intermediate configuration to allow setLoRaWAN to reset the LoRaWAN module when joinOTAA fails
    setLoRaWAN(F("  - Save configuration"), &WaspLoRaWAN::saveConfig);
    blinkLed(stage++);
    setLoRaWAN(F("  - Join OTAA"), &WaspLoRaWAN::joinOTAA);
    setLoRaWAN(F("  - Save configuration"), &WaspLoRaWAN::saveConfig);
    blinkLed(stage++);
}

void readSensor(uint16_t sensor, RunningMedian &samples) {
    USB.print(F("  "));
    samples.clear();
    // Initiate a dummy reading for analog-to-digital converter channel selection
    SensorGasv20.readValue(sensor);
    for (uint8_t i = 0; i < samples.getSize(); i++) {
        // Returns the voltage read at the sensor output or load resistor, or -1.0 for error in sensor type selection
        float f = SensorGasv20.readValue(sensor);
        samples.add(f);
        flashLed();
        printFloat(F("  "), f);
        delay(1000);
    }
    USB.println();
    printInt(F("    count="), samples.getSize());
    printFloat(F("  mean="), samples.getAverage());
    printFloat(F("  median="), samples.getMedian());
    printFloat(F("  min="), samples.getLowest());
    printFloat(F("  max="), samples.getHighest());
    USB.println();
}

uint8_t setSampleData(RunningMedian samples, uint8_t i) {
    int16_t median = samples.getMedian() * 100;
    int16_t min = samples.getLowest() * 100;
    int16_t max = samples.getHighest() * 100;

    data[i++] = min >> 8;
    data[i++] = min;
    data[i++] = median >> 8;
    data[i++] = median;
    data[i++] = max >> 8;
    data[i++] = max;
    return i;
}

/**
 * Takes all measurements, and populates the LoRaWAN data.
 *
 * @return the length of the data
 */
uint8_t takeMeasurements() {
    printMemory();

    // Turn on the sensor board
    SensorGasv20.ON();
    USB.printf("  - Power on sensor board (waiting %u seconds for stabilization)\n", boardInitSeconds);
    USB.flush();
    delay(1000L * boardInitSeconds);

    // Temperature
    blinkLed(stage++);
    USB.println(F("  - Temperature"));
    RunningMedian temperatureSamples = RunningMedian(temperatureSampleCount);
    readSensor(SENS_TEMPERATURE, temperatureSamples);

    // Atmospheric pressure
    blinkLed(stage++);
    USB.println(F("  - Atmospheric pressure"));
    SensorGasv20.setSensorMode(SENS_ON, SENS_PRESSURE);
    delay(30);

    RunningMedian pressureSamples = RunningMedian(pressureSampleCount);
    readSensor(SENS_PRESSURE, pressureSamples);

    SensorGasv20.setSensorMode(SENS_OFF, SENS_PRESSURE);

    // NO2
    blinkLed(stage++);
    char no2LoadResistorString[6];
    Utils.float2String(no2LoadResistor, no2LoadResistorString, 2);
    USB.printf("  - NO2 (gain %u; load resistor %s kOhm; waiting %u seconds for stabilization/preheating)\n",
               no2Gain, no2LoadResistorString, no2InitSeconds);
    SensorGasv20.configureSensor(SENS_SOCKET3B, no2Gain, no2LoadResistor);
    SensorGasv20.setSensorMode(SENS_ON, SENS_SOCKET3B);
    USB.flush();
    delay(1000L * no2InitSeconds);

    RunningMedian no2Samples = RunningMedian(no2SampleCount);
    readSensor(SENS_SOCKET3B, no2Samples);

    SensorGasv20.setSensorMode(SENS_OFF, SENS_SOCKET3B);

    // Turn off sensor board
    USB.println(F("  - Switch off sensor board"));
    SensorGasv20.OFF();
    delay(10);

    // Battery
    USB.println(F("  - Battery"));
    USB.print(F("  "));
    // First dummy reading for analog-to-digital converter channel selection
    PWR.getBatteryLevel();
    flashLed();
    uint8_t batteryLevel = PWR.getBatteryLevel();
    printInt(F("  "), batteryLevel);
    printFloat(F("% ("), PWR.getBatteryVolts());
    USB.println(" Volt)");

    // Prepare a LoRaWAN message; MSB
    uint8_t i = 0;
    i = setSampleData(temperatureSamples, i);
    i = setSampleData(pressureSamples, i);
    i = setSampleData(no2Samples, i);
    data[i++] = batteryLevel;
    return i;
}

void loop() {
    stage = 1;
    blinkLed(stage++);

    // Turn on the RTC to avoid possible conflicts in the I2C bus. See "6. Board configuration and programming" in
    // "gases-sensor-board-2.0.pdf". The RTC will be powered off again when going into deep sleep.
    RTC.ON();
    // Small stabilization delay
    delay(100);

    USB.print(F("\nTaking measurements "));
    USB.println(RTC.getTime());

    uint8_t dataLen = takeMeasurements();

    // In the Waspmote API v23, data must be passed as a HEX string.
    char text[100];
    Utils.hex2str((uint8_t *) data, text, dataLen);

    blinkLed(stage++);
    USB.println(F("\nSending measurements"));
    setLoRaWAN(F("  - Switch on LoRaWAN module"), &WaspLoRaWAN::ON, socket);
    setLoRaWAN(F("  - Set ABP keys"), &WaspLoRaWAN::joinABP);
    getLoRaWAN(F("  - Application EUI"), &WaspLoRaWAN::getAppEUI, LoRaWAN._appEUI);
    getLoRaWAN(F("  - Device EUI"), &WaspLoRaWAN::getDeviceEUI, LoRaWAN._devEUI);
    getLoRaWAN(F("  - Device Address"), &WaspLoRaWAN::getDeviceAddr, LoRaWAN._devAddr);
    getLoRaWAN(F("  - Uplink counter"), &WaspLoRaWAN::getUpCounter, &LoRaWAN._upCounter);
    getLoRaWAN(F("  - Downlink counter"), &WaspLoRaWAN::getDownCounter, &LoRaWAN._downCounter);

    USB.print(F("  - Sending packet "));
    USB.print(text);

    // Only try sending once
    uint8_t result = LoRaWAN.sendUnconfirmed(PORT, text);
    USB.print(F(": "));
    printLoRaWANResult(result);

    if (result != LORAWAN_ANSWER_OK) {
        // As we're using blinkLed(stage++), the current value for stage is one too high:
        blinkLedError(stage - 1);
    } else {
        if (LoRaWAN._dataReceived) {
            USB.print(F("  - Received downlink on port "));
            USB.println(LoRaWAN._port, DEC);
            USB.print(F("    "));
            USB.println(LoRaWAN._data);
        }
    }

    getLoRaWAN(F("  - Uplink counter"), &WaspLoRaWAN::getUpCounter, &LoRaWAN._upCounter);
    getLoRaWAN(F("  - Downlink counter"), &WaspLoRaWAN::getDownCounter, &LoRaWAN._downCounter);

    // Do we really want to repeat this until we get success?
    setLoRaWAN(F("  - Switch off LoRaWAN module"), &WaspLoRaWAN::OFF, socket);

    printMemory();

    USB.print(F("\nEntering deep sleep for "));
    USB.println(sleepTime);
    USB.flush();
    // Deep sleep with all sensors off
    PWR.deepSleep(sleepTime, RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
    // UART is closed during sleep, so open it again
    USB.ON();
    USB.println("\nWake up");
}
