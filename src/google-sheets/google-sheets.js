/**
 * Handles data from a HTTP POST, invoked by the The Things Network's HTTP Integration.
 *
 * This will create a new sheet for each month worth of data, using the timezone defined below.
 *
 * Usage:
 *
 *   1. In a Google Sheets spreadsheet go to menu Tools, Script editor.
 *
 *   2. Replace the example code with this very script.
 *
 *   3. Save the code (e.g., Ctrl+S or Cmd+S).
 *
 *   4. Menu Publish, Deploy as web app:
 *      - "Project version: new"
 *      - "Execute the app as: me"
 *      - "Who has access to the app: anyone, even anonymously"
 *
 *   5. Copy the "Current web app URL" and use this as the endpoint URL of the HTTP Integration in
 *      The Things Network's TTN Console.
 *
 *   6. Whenever making changes, repeat step 4 and ALWAYS select "Project version: new"
 *
 * Notes:
 *
 *   - Upon success this script returns some JSON, which makes Google issue a 301 Moved Temporarily.
 *
 *   - When hitting the rate limit, Google returns 200 OK with a human-readable message.
 *
 *   - Even when an error occurs in the script, Google will return a 200 OK, so this script sends an
 *     email to the spreadsheet's owner instead.
 *
 *   - This assumes the V8 runtime (not the older Rhino runtime), available since February 2020; see
 *     https://developers.google.com/apps-script/releases#february_5_2020
 *
 *   - Based on https://www.geogebra.org/m/fkSaFhqF and its references. Those, and most other (old)
 *     examples, show some `setup` function to get the current document identifier. But that is no
 *     longer required for scripts that are attached to the context of a Google Sheet anyway, due to
 *     creating the script using Tools, Script editor.
 */

/**
 * The timezone to use when handling dates.
 */
const TZ = "Europe/Amsterdam";

/**
 * The format for (monthly) sheet names.
 */
const SHEET_NAME_FORMAT = "yyyy-MM";

/**
 * The zero-based index when inserting a new (monthly) sheet, here assuming the first two sheets are
 * used for some documentation and results sheets.
 */
const NEW_SHEET_INDEX = 2;

/**
 * Gets or creates a sheet for the given ISO8601 timestamp, using the timezone defined above, such
 * as "2018-11" for "2018-10-31T23:30:50Z" and Europe/Amsterdam.
 *
 * @param timestamp an ISO8601 formatted string
 */
function getSheet(timestamp) {
  const utc = new Date(timestamp);
  const sheetName = Utilities.formatDate(utc, TZ, SHEET_NAME_FORMAT);
  const doc = SpreadsheetApp.getActiveSpreadsheet();
  return doc.getSheetByName(sheetName) || doc.insertSheet(sheetName, NEW_SHEET_INDEX);
}

/**
 * Returns the first value that is not undefined and not null.
 */
function coalesce(...values) {
  return values.find(v => v !== undefined && v !== null);
}

/**
 * @see https://developers.google.com/apps-script/guides/web
 */
function doGet(e) {
  return ContentService.createTextOutput("This endpoint requires HTTP POST");
}

/**
 * @see https://developers.google.com/apps-script/guides/web
 */
function doPost(e) {
  // A lock that prevents any user from concurrently running a section of code.
  const lock = LockService.getScriptLock();
  try {
    // Wait at most 5 seconds to get the lock to prevent concurrent script access overwriting data.
    lock.waitLock(5000);

    const data = JSON.parse(e.postData.contents);
    // This assumes a payload function in TTN Console. Alternatively, one could also decode
    // data.payload_raw (which is Base64 encoded).
    const fields = data.payload_fields;
    const metadata = data.metadata;
    const gateways = metadata.gateways;

    const sheet = getSheet(metadata.time);

    // Create or update the header. (One could also use the header to define the attribute names as
    // used in the data, though that would require an exact match between header and data, and
    // require the sheet, or some template, to already exist before the data is pushed.)
    const headerRow = [];
    headerRow.push("time");
    headerRow.push("device id");
    headerRow.push("counter");

    headerRow.push("NO2 min");
    headerRow.push("NO2 median");
    headerRow.push("NO2 max");
    headerRow.push("P min");
    headerRow.push("P median");
    headerRow.push("P max");
    headerRow.push("T min");
    headerRow.push("T median");
    headerRow.push("T max");
    headerRow.push("battery");

    headerRow.push("frequency");
    headerRow.push("modulation");
    headerRow.push("data rate");
    headerRow.push("coding rate");

    // A single uplink may have been received by multiple gateways; map those to multiple groups of
    // columns. The sort order is undefined.
    headerRow.push("gateway count");
    for (let i = 0; i < gateways.length; i++) {
      headerRow.push(`gateway id ${i}`);
      headerRow.push(`RSSI ${i}`);
      headerRow.push(`SNR ${i}`);
      headerRow.push(`latitude ${i}`);
      headerRow.push(`longitude ${i}`);
      headerRow.push(`altitude ${i}`);
    }

    // Overwrite the header in the leftmost part of row 1, preserving anything that might exist more
    // to the right (specifically headers for some 2nd, 3rd, ..., group of gateway details, which
    // might not apply to this very uplink but were added for earlier data).
    sheet.getRange(1, 1, 1, headerRow.length).setValues([headerRow]);

    // Populate a new data row
    const row = [];
    // Default formatting might only display the date part. Still, for usage in time series graphs,
    // this is better than a text value.
    row.push(new Date(metadata.time));
    row.push(data.dev_id);
    row.push(data.counter);

    row.push(fields.no2.min);
    // Backwards compatibility for 2017 messages, which had a value in no2, and early 2018 messages
    // that used an average rather than a median.
    row.push(coalesce(fields.no2.median, fields.no2.avg, fields.no2));
    row.push(fields.no2.max);
    row.push(fields.pressure.min);
    row.push(coalesce(fields.pressure.median, fields.pressure.avg, fields.pressure));
    row.push(fields.pressure.max);
    row.push(fields.temperature.min);
    row.push(coalesce(fields.temperature.median, fields.temperature.avg, fields.temperature));
    row.push(fields.temperature.max);
    row.push(fields.battery);

    row.push(metadata.frequency);
    row.push(metadata.modulation);
    row.push(metadata.data_rate);
    row.push(metadata.coding_rate);

    row.push(gateways.length);
    for (const gateway of gateways) {
      row.push(gateway.gtw_id);
      row.push(gateway.rssi);
      row.push(gateway.snr);
      row.push(gateway.latitude);
      row.push(gateway.longitude);
      // Not always available
      row.push(gateway.altitude);
    }

    // Add new data at the bottom
    const nextRow = sheet.getLastRow() + 1;

    // Or, to add at the top (which is VERY slow for large number of rows, but nicely extends any
    // existing ranges, like when used in charts):
    // sheet.insertRowAfter(1);
    // const nextRow = 2;

    sheet.getRange(nextRow, 1, 1, row.length).setValues([row]);

    // Return some JSON success result; ignored by the the HTTP Integration. Scripts cannot directly
    // return text content to a browser. Instead, the browser is directed to googleusercontent.com,
    // which will display it without any further sanitization or manipulation. So, this will yield a
    // 301 Moved for a successful invocation.
    return ContentService.createTextOutput(
      JSON.stringify({result: "success", row: nextRow})
    ).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    // Even re-throwing the error yields a 200 OK for the client, with the error in some HTML
    // content; see https://issuetracker.google.com/issues/36759757 Also, TTN does not provide any
    // way to access some logs of the integration. So, send an email to the owner of the sheet (who
    // will also be the sender of the message).
    const owner = Session.getEffectiveUser().getEmail();
    GmailApp.sendEmail(owner, "An error occurred in your Google Apps script",
      `POST data: ${e.postData ? e.postData.contents : ""}

Error: ${error}`);

    return ContentService.createTextOutput(
      JSON.stringify({result: "error", error: error})
    ).setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}
