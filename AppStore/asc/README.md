# asc — App Store Connect helper

Small Swift CLI that fills the App Store listing from `../listing.json` and uploads screenshots.

```bash
swiftc -O main.swift -o asc            # needs ~/private_keys/AuthKey_<KEY_ID>.p8
./asc status                            # app, versions, builds, localizations
./asc sync ../listing.json <shots dir>  # shots dir has iphone/, ipad/, mac/ subfolders of PNGs
./asc finalize IOS 1.4                  # attach newest build, age rating 4+, content rights
./asc prepare IOS 1.4                   # copyright, review contact, free price
./asc submit IOS 1.4                    # submit for review (App Privacy must be answered in the UI first)
./asc get /v1/apps                      # raw GET for debugging
```

`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_BUNDLE_ID` override the defaults.
