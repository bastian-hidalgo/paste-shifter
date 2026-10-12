# Mac App Store release readiness

Last reviewed: 2026-10-12

## Current status

The App Store-specific configuration now builds a sandboxed edition and an App Store Connect package. The store edition removes global event taps and synthetic keyboard events. It copies the selected history item to the system clipboard; the user switches to the destination app and presses ⌘V. This changes the original direct distribution interaction model.

The archive and export for **0.5.6 (14)** exist at `dist/AppStore/Paste Shifter 0.5.6 (14).xcarchive` and `dist/AppStore/Export 0.5.6 (14)/Paste Shifter.pkg`. The export summary records the Mac App Store provisioning profile and App Sandbox entitlement; Apple processing completed and the build is attached to App Store Connect. App Store Connect record **Paste Shifter** (app ID `6821711381`) has the Spanish listing, US base price of **$0.99** with Apple's comparable prices, export-compliance answer for the Apple OS-provided CryptoKit path, live privacy/support URLs, published no-data-collected declaration, and saved review contact details and notes. Four screenshots are present in the macOS listing, ordered Normal, Fantasma, Flash, Ajustes. The seller chose to sell Paste Shifter as a commercial product of Visitme SpA. The content-rights declaration is saved as Yes, based on the seller's confirmation that users provide and are authorized to use the clipboard content. The seller authorized disclosure of registered business contacts under DSA. The version is not yet submitted, the paid apps agreement is marked **New**, and App Store Connect says the legal entity information must be updated before the agreement can be signed. Although the account's compliance table says Active, the DSA detail dialog currently has “No soy un comerciante” selected; the seller chose trader status, so this must be changed and verified after the legal address is corrected.

## Release gates

- [x] Implement an App Store interaction model that works without global event taps or synthetic keyboard/mouse events.
- [x] Enable App Sandbox and define the App Store entitlements.
- [x] Compile, archive, and export an App Store Connect package.
- [ ] Verify the exported sandboxed app's supported history selection and paste flow. The archived build was launched with its isolated `--demo` mode, which seeds sample entries without reading or writing the system clipboard; its Settings window appeared. This verifies launch and the settings UI, but the history picker interaction and destination-app ⌘V flow remain unverified.
- [x] Export with Xcode automatic signing and a Mac App Store provisioning profile for `cl.pasteshifter.app`.
- [x] Sign in to App Store Connect and create the app record (SKU `cl.pasteshifter.app`).
- [ ] Review/update the legal entity information and accept the paid-app agreement. App Store Connect currently marks it **New** and requires an entity-information update before signing.
- [x] Finish listing URLs and privacy disclosures. Privacy policy: https://bastian-hidalgo.github.io/paste-shifter/privacy.html. Support: https://bastian-hidalgo.github.io/paste-shifter/support.html. Website: https://bastian-hidalgo.github.io/paste-shifter/.
- [x] Upload four genuine macOS app screenshots to App Store Connect; the listing shows 4 of 10, ordered Normal, Fantasma, Flash, Ajustes.
- [x] Set the App Store category to Productivity and complete the age-rating questionnaire (4+).
- [x] Confirm the “no data collected” privacy declaration and publish it in App Store Connect, based on the seller's explicit confirmation.
- [x] Select the United States as the base territory at $0.99 USD, with Apple's comparable prices across all territories.
- [x] Upload build 0.5.5 (13) with Transporter.
- [x] Confirm Apple's processing finishes: build 0.5.5 (13) is ready for internal testing.
- [x] Archive and export version 0.5.6 (14).
- [x] Deliver build 0.5.6 (14) to App Store Connect with Transporter.
- [x] Confirm Apple's processing finishes for build 0.5.6 (14); status is ready for submission.
- [x] Answer the build's export-compliance questionnaire in App Store Connect. CryptoKit/AES-GCM uses Apple's OS-provided crypto; the build no longer shows “Missing Export Compliance.”
- [x] Attach build 0.5.6 (14) to the 0.5.6 version draft and save it.
- [x] Save App Review contact information and review notes.
- [x] Save App Store Connect's content-rights declaration. Paste Shifter handles user-selected clipboard text only when the user is authorized to use it; Visitme does not provide or distribute a third-party content catalog.
- [ ] Complete the seller's EU Digital Services Act trader declaration and verification for this app. The seller chose to sell Paste Shifter as a commercial product of Visitme SpA and authorized use of the registered legal address and existing business contacts. App Store Connect currently has “No soy un comerciante” selected; change it to trader after the updated legal address appears. The contact form contains the registered business phone and email. The Account Holder must enter Apple's email code directly, then complete phone verification and upload the requested business verification document.
- [ ] Update legal entity details and sign the Paid Apps agreement as Account Holder. The seller reports correcting the address, but a fresh App Store Connect load still shows the previous address, city “N/A”, and blank region/postal code; the legal-entity dialog marks the street field invalid and Save disabled. The DSA contact form says address changes must be made through Dun & Bradstreet. The agreement remains **New**; accepting it is a legally binding account action.
- [ ] Verify the exported sandboxed app's supported user flow, then submit the completed version for review.

## Verified project facts

- Bundle ID: `cl.pasteshifter.app`; deployment target: macOS 13.
- Current version/build: 0.5.6 (14); prior build 0.5.5 (13) remains available in App Store Connect.
- Current signing team: `BJ345NMP76`; project uses automatic signing.
- Existing icon source: `Resources/AppIcon-Purple.png`.
- Four store screenshots are in `Store/Screenshots/upload/`; App Store Connect shows 4 of 10 for macOS.
- App Store Connect app ID: `6821711381`; bundle ID: `cl.pasteshifter.app`; version/build: `0.5.6 (14)`.
- The seller account is VISITME SpA. A separate Visitme iOS app is also in this seller account; do not edit it while preparing Paste Shifter.
- The app record creation flow did not save the restricted user-access setting; the app is currently available to all seller users, which is appropriate for this public listing.
- The seller explicitly confirmed no data is collected outside the Mac. App Store Connect's matching privacy declaration is now published.
- Apple documents the US price range starting at $0.99; the paid-app agreement must be accepted by the Account Holder before selling. [Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)
- The project uses AES-GCM through Apple's CryptoKit for local Private history. App Store Connect's export questionnaire was answered for the OS-provided crypto path; Apple's reference says this path needs no uploaded French encryption declaration. Reassess if the implementation or distribution territories change. [Apple export-compliance reference](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)
- The previously installed Debug app's Settings and Normal history windows were visible in this desktop session. Normal contained live user content, so it was not used for the public screenshot. The repository's `Store/Screenshots/preview.html` is a visual concept and is not a genuine app screenshot. The exported sandboxed app launched in isolated `--demo` mode and showed Settings; its history selection and destination-app paste interaction remain unverified. App Store Connect shows four uploaded screenshots and the saved content-rights declaration. Legal address correction is being handled directly by the seller. DSA trader status and email/phone/document verification remain incomplete; the Account Holder must enter Apple's email code in App Store Connect. The paid apps agreement remains **New** pending legal-entity updates and acceptance by the Account Holder.

## Apple references

- [App Sandbox requirement and design](https://developer.apple.com/documentation/security/app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- [App pricing and availability](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability/)
- [App privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
