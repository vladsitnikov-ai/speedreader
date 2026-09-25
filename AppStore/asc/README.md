# asc — App Store Connect helper

Small Swift CLI that fills the App Store listing from `../listing.json` and uploads screenshots.

```bash
swiftc -O main.swift -o asc            # needs ~/private_keys/AuthKey_<KEY_ID>.p8
./asc status                            # app, versions, builds, localizations
./asc sync ../listing.json <shots dir>  # shots dir has iphone/, ipad/, mac/ subfolders of PNGs
./asc finalize IOS 1.4                  # attach newest build, age rating 4+, content rights
```

`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_BUNDLE_ID` override the defaults.
