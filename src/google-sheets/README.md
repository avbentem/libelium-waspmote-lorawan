# Google Sheets example

Google Sheets can be set up to accept HTTPS POST push messages from The Things Network, using the HTTP Integration in
TTN Console. The example code in [google-sheets.js](google-sheets.js) explains more.

## Example JSON payload

```json
{
  "app_id": "haarlem-app-2",
  "dev_id": "haarlem-waspmote-1-24-139",
  "hardware_serial": "0004A30B001BA5E3",
  "port": 1,
  "counter": 921,
  "payload_raw": "B48HrwgwKXUpmSsUBo0G7gdvYQ==",
  "payload_fields": {
    "battery": 97,
    "no2": {
      "max": 19.03,
      "median": 17.74,
      "min": 16.77
    },
    "pressure": {
      "max": 110.28,
      "median": 106.49,
      "min": 106.13
    },
    "temperature": {
      "max": 20.96,
      "median": 19.67,
      "min": 19.35
    }
  },
  "metadata": {
    "time": "2018-10-21T21:21:13.409323001Z",
    "frequency": 867.1,
    "modulation": "LORA",
    "data_rate": "SF9BW125",
    "coding_rate": "4/5",
    "gateways": [
      {
        "gtw_id": "eui-0000024b080606d8",
        "timestamp": 2233757020,
        "time": "2018-10-21T21:21:13.391458Z",
        "channel": 3,
        "rssi": -119,
        "snr": -12.2,
        "rf_chain": 0,
        "latitude": 52.3817,
        "longitude": 4.62979,
        "altitude": 13
      },
      {
        "gtw_id": "arjanvanb-gw-1",
        "gtw_trusted": true,
        "timestamp": 2497256444,
        "time": "2018-10-21T21:21:14Z",
        "channel": 3,
        "rssi": -61,
        "snr": 8.75,
        "rf_chain": 0,
        "latitude": 52.374485,
        "longitude": 4.635738,
        "location_source": "registry"
      }
    ]
  },
  "downlink_url": "https://integrations.thethingsnetwork.org/ttn-eu/api/v2/down/haarlem-app-2/haarlem-waspmote-1-24-139?key=ttn-account-v2.REDACTED"
}
``` 