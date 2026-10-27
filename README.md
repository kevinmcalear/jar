# Jar

A private spending game for two iPhones. Each day is a pile of bills. What is left gets shoved into one shared jar.

Open `Jar.xcodeproj` in Xcode 27. The deployment target is iOS 27.0.

```
xcodebuild -scheme Jar -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme JarChecks -destination 'platform=macOS' build
```

CloudKit container: `iCloud.com.kevinmcalear.dailyjar`. Amounts are encrypted on the phone before they upload. The push says an entry changed, and the phone fills in the card after it decrypts. Jar does not log into a bank.
