// The beta ships through TestFlight, which invites by Apple ID, so the waitlist asks for the
// iCloud address (icloud.com, plus the older me.com / mac.com aliases that are also iCloud
// mailboxes). Keep this in sync with the `waitlist` rule in firestore.rules.
export const ICLOUD_RE = /^[^@\s]+@(icloud|me|mac)\.com$/i

export function isIcloudEmail(value) {
  return ICLOUD_RE.test(value.trim())
}
