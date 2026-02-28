# Offline Reddit Reader 📱

A fully custom, offline-first iOS Reddit client built natively with SwiftUI and SwiftData. 

This app is designed to fetch your favorite subreddits (or multi-reddits) and permanently cache the posts, images, and comment trees to your device so you can read them on airplanes, the subway, or anywhere else with zero cell service.

### ✨ Features
* **Smart Offline Caching:** Automatically downloads top posts, high-res image galleries, and deep comment threads using SwiftData.
* **Zen Reading Mode:** One-tap toggle to hide usernames, avatars, and visual clutter for pure text reading.
* **Advanced Comment Navigation:** Tap to collapse individual comment trees, or use deep-swipes to instantly collapse a thread and jump to the next parent comment.
* **Intelligent Subreddit Validation:** Native integration with Reddit's search API to auto-correct typos when adding new communities (e.g., suggesting `apple` if you type `aple`).

### 🛠️ How to Install (For Developers)
Because this app is not on the App Store, you will need Xcode to compile and sign it for your personal device.

1. Click the green **Code** button above and select **Download ZIP** (or clone the repo).
2. Open the `OfflineReddit.xcodeproj` file in Xcode (macOS only).
3. Plug your iPhone into your Mac.
4. In Xcode, click on the **OfflineReddit** project file in the left sidebar.
5. Go to the **Signing & Capabilities** tab.
6. Check the box for "Automatically manage signing" and select your personal Apple ID from the **Team** dropdown.
7. Select your iPhone from the device list at the top of the window and hit **Cmd + R** to Build and Run!
