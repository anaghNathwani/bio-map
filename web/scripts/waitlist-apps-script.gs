/**
 * Appends "Join the waitlist" signups from the website straight into this Google Sheet:
 * https://docs.google.com/spreadsheets/d/1L73YhfQAGtDU_yJgfFpBn2FL8SPYWU847Lf_FXbUofU/edit
 *
 * This file is not run by anything in this repo — it's kept here for version control. The actual
 * code has to live inside the spreadsheet's own Apps Script project, because only that gives it
 * permission to write to the sheet without a service account or any other credential to manage.
 *
 * ONE-TIME SETUP (about a minute, done signed in to the Google account that owns the sheet):
 *   1. Open the sheet above -> Extensions -> Apps Script.
 *   2. Delete the placeholder "myFunction() {}" and paste this whole file in its place.
 *   3. Deploy -> New deployment -> gear icon -> "Web app".
 *        - Execute as: Me
 *        - Who has access: Anyone
 *      Deploy, and approve the permission prompt (it's asking to let this script, which you just
 *      pasted in, edit this one spreadsheet — that's the whole point of it).
 *   4. Copy the "Web app URL" it gives you (ends in /exec).
 *   5. Put that URL in web/.env.local (and in the Firebase Hosting build's env) as:
 *        VITE_WAITLIST_SCRIPT_URL=https://script.google.com/macros/s/XXXXXXXX/exec
 *      then rebuild/redeploy the site. See web/.env.example.
 *
 * If the form's fields ever change, update the HEADERS array below to match — a header row is
 * only written once, the first time the sheet is empty.
 */

var SHEET_NAME = 'Waitlist'
var HEADERS = ['Timestamp', 'Email', 'Name', 'Source']

function doGet(e) {
  var email = (e.parameter.email || '').trim()
  if (!email || email.indexOf('@') === -1) {
    return respond({ ok: false, error: 'A valid email is required.' })
  }

  var sheet = getOrCreateSheet()
  var existingRow = findRowByEmail(sheet, email)
  var name = (e.parameter.name || '').trim()
  var source = (e.parameter.source || 'website').trim()

  if (existingRow) {
    // Already on the list — refresh their name/timestamp rather than adding a duplicate row.
    sheet.getRange(existingRow, 1, 1, HEADERS.length).setValues([[new Date(), email, name, source]])
  } else {
    sheet.appendRow([new Date(), email, name, source])
  }

  return respond({ ok: true })
}

function getOrCreateSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet()
  var sheet = ss.getSheetByName(SHEET_NAME)
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME)
  if (sheet.getLastRow() === 0) sheet.appendRow(HEADERS)
  return sheet
}

function findRowByEmail(sheet, email) {
  var lastRow = sheet.getLastRow()
  if (lastRow < 2) return null
  var emails = sheet.getRange(2, 2, lastRow - 1, 1).getValues()
  for (var i = 0; i < emails.length; i++) {
    if (String(emails[i][0]).toLowerCase() === email.toLowerCase()) return i + 2
  }
  return null
}

function respond(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON)
}
