# App Store Listing — Edge Mind Ai

> Paste-ready metadata for App Store Connect → your app → **App Store** tab → **iOS App** (version 0.1.0).
> Anything in `[brackets]` you must fill in (URLs, contact, demo account).

---

## 1. App Information

| Field | Value |
|---|---|
| **App Name** | `Edge Mind Ai` |
| **Subtitle** | `Private on-device AI assistant` |
| **Bundle ID** | `com.vinothrajalingam.EdgeMindAi` (already selected) |
| **Primary Language** | English (U.S.) |
| **SKU** | `edgemindai-edge-001` |
| **Primary Category** | `Productivity` |
| **Secondary Category** | `Utilities` |
| **Content Rights** | `Does not contain third-party content` (you own/curate the catalog) |
| **Copyright** | `© 2026 Vinoth Rajalingam` |
| **Price** | `Free` |
| **Privacy Policy URL** | `[REQUIRED — host the text in §7 below at a public URL, e.g. https://vinoth12940.github.io/EdgeMind-Ai/privacy.html — paste that URL here]` |
| **Support URL** | `[REQUIRED — e.g. https://github.com/vinoth12940/EdgeMind-Ai/issues or a mailto:vinoth.rajalingam@icloud.com]` |
| **Marketing URL** | `[OPTIONAL — e.g. your GitHub repo URL]` |

---

## 2. Promotional Text (≤170 chars, editable without new review)

```
Your private AI runs entirely on-device. Stream local LLMs, attach photos for vision chat, dictate by voice — no cloud, no accounts, fully offline by default.
```

---

## 3. Description (≤4000 chars)

```
Edge Mind Ai is a privacy-first AI assistant that runs entirely on your iPhone and iPad. Your conversations, prompts, and photos never leave your device — all AI inference happens locally on Apple Silicon. There is no cloud server, no account required, and no data collection.

RUN 20+ MODELS, LOCALLY
Choose from a curated catalog of 21 open models from Apple Intelligence, Google Gemma, IBM Granite, Meta Llama, Microsoft Phi, DeepSeek, Mistral, Qwen, SmolLM, and Liquid AI. Switch between them mid-conversation. Download only the ones you want; delete them anytime to reclaim space.

REAL CHAT, NOT A WRAPPER
• Token-by-token streaming responses
• Full Markdown rendering with code blocks and syntax highlighting
• Multiple conversations — create, rename, and resume sessions from History
• Attach a photo from your camera or library and ask a vision model about it
• Voice dictation — speak your prompt; responses read back via on-device speech

PRIVACY IS THE DEFAULT
• Fully offline out of the box. Nothing is uploaded unless you turn on Live Search.
• No telemetry, no analytics, no cloud sync, no login required.
• A guest profile gets you chatting in one tap.
• Optional Face ID / Touch ID / local credentials to protect your space.
• Your HuggingFace token (for gated model downloads) is stored in the iOS Keychain.

OPTIMIZED FOR YOUR DEVICE
Edge Mind Ai detects your chip and tunes itself automatically — context windows of 2K–8K tokens and flash-attention acceleration on supported devices, so large models run within your iPhone's memory without crashing.

OPTIONAL LIVE WEB SEARCH
Turn on web grounding per prompt when you need fresh information. Bring your own key for Tavily, Brave Search, Serper (Google), or a self-hosted gateway. Search results come back with inline source citations. It's off by default — your AI stays local unless you ask it to look something up.

CURATED, NOT THE WILD WEST
The model catalog is hand-picked and capability-audited for this app's runtime. Thinking models stream a reasoning lane; vision models accept images; tool-calling models can trigger web search. Badges reflect what the app actually supports, not just marketing claims.

WHO IT'S FOR
• Privacy-conscious users who want ChatGPT-style help without sending data to a server
• Developers and researchers experimenting with local LLMs on iOS
• Anyone who needs an AI assistant that works on a plane, underground, or offline
• People who want to own their AI — models live on your device, under your control

REQUIRES iPhone or iPad with iOS 17 or later and an A14 chip or newer for best results. MLX models run on physical Apple Silicon only (not the simulator). Apple Intelligence model requires a compatible device.

Edge Mind Ai is an independent project. It is not affiliated with or endorsed by Apple, Google, Meta, Microsoft, IBM, Alibaba, Mistral, Hugging Face, or Liquid AI. Model weights are the property of their respective creators and are loaded under their original licenses.
```

---

## 4. Keywords (≤100 chars, comma-separated)

```
on-device AI,offline AI,local LLM,private chat,AI assistant,MLX,llama,vision,voice,offline,chatbot,no internet
```
> Don't include "Edge" "Mind" or "Ai" — Apple already matches those from your app name and ignores duplicates.

---

## 5. What's New in This Version

```
• Initial App Store release
• 21-model local catalog (Apple Intelligence, Gemma, Llama, Qwen, Phi, Granite, Mistral, DeepSeek, SmolLM, LFM)
• Streaming chat with Markdown and code highlighting
• Vision chat via camera/photo attachment
• Voice dictation and text-to-speech playback
• Optional Live Web Search with citations (Tavily / Brave / Serper / custom)
• Guest, local-credential, and Face ID / Touch ID sign-in
• Dark-mode-first design system
```

---

## 6. Age Rating — Content Descriptions

Select these in the Age Rating questionnaire. Result: **12+**

| Content | Answer |
|---|---|
| Cartoon / Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged / Graphic / Sadistic Realistic Violence | None |
| Profanity / Crude Humor | **Infrequent / Mild** |
| Mature / Suggestive Themes | **Infrequent / Mild** |
| Horror / Fear Themes | None |
| Medical / Treatment Information | None |
| Alcohol / Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content | None |
| Unrestricted Web Access | **No** (search API with citations, not a browser — keeps rating at 12+) |
| Gambling with Real Currency | No |

> Rating: **12+**. If App Review argues that an unfiltered local LLM needs 17+, bump "Mature/Suggestive Themes" to Frequent/Intense → rating becomes 17+. Prefer 12+ first.

---

## 7. Encryption Attestation

When asked *"Is your app designed to use cryptography or does it contain or incorporate cryptography?"*:

**Answer: Yes** → then select the **exemption**:

```
This app qualifies for the exemption under Export Administration Regulation (EAR) clause 740.13(e) / BIS Item Type 5D002. It uses encryption only via standard, built-in iOS networking (HTTPS/TLS via URLSession and the system networking stack) and Apple Foundation/ML frameworks. It does not implement, add to, or customize any proprietary or non-standard cryptographic functionality. It does not use proprietary encryption algorithms. The on-device AI model files (GGUF/MLX weights) are numeric tensor data, not executable cryptographic code.
```

Then enable: *"My app is exempt from the encryption export reporting requirement because it uses only standard HTTPS/TLS."*

---

## 8. App Review Information

**Contact**
| Field | Value |
|---|---|
| First Name | `Vinoth` |
| Last Name | `Rajalingam` |
| Email | `vinoth.rajalingam@icloud.com` |
| Phone | `[your phone number with country code]` |

**Demo Account:** *None required* — the app opens directly into a guest chat workspace. No account, email, or login needed to test.

**Notes to Reviewer** (paste this verbatim):

```
Thank you for reviewing Edge Mind Ai.

NO ACCOUNT NEEDED
The app opens directly into a local chat workspace with an anonymous on-device guest profile. Tap "Guest" or just begin — no email, login, or remote authentication is required.

TEST INSTANTLY — NO DOWNLOAD
The default active model is "Apple Intelligence" (the system Foundation Model). Send a prompt like "Hello on-device AI!" and you'll get an instant local reply with nothing downloaded. This runs fully offline.

VOICE
Tap the microphone in the chat composer, allow Speech Recognition + Microphone, and speak a prompt. Responses can be played back via iOS text-to-speech.

OPTIONAL MODEL DOWNLOADS (Models tab)
The Models tab lists a curated catalog of ~21 local models. For quick testing we recommend "LFM2.5 350M (MLX)" (~0.4 GB) or "Granite 3.3 2B (MLX)" (~1.4 GB). Some gated models (Phi, LFM) require a free HuggingFace token entered in Settings. Vision models (Qwen 3.5 VL, LFM2.5 VL, Gemma LiteRT) expose camera/photo image attachment.

IMPORTANT — MLX REQUIRES A PHYSICAL DEVICE
Apple's MLX framework does not run on the Xcode Simulator (hardware-acceleration constraint). On the Simulator, GGUF models and Apple Intelligence work; MLX models appear grayed out. PLEASE TEST MLX ON A PHYSICAL iPhone 12 or newer running iOS 17+.

GUIDELINE 2.5.2 — STATIC MODEL WEIGHTS
Downloaded GGUF/MLX/LiteRT weights are numeric tensor data files (matrices), not executable code. They are parsed by the app's precompiled native libraries and do not modify the app's execution paths or download new binaries.

PRIVACY
Fully offline by default. No telemetry, analytics, cloud sync, or account. Live Web Search is OFF unless the user enables it per prompt and supplies their own search-provider API key. HuggingFace tokens are stored in the iOS Keychain. Camera/microphone/photos/Face ID are used only for the user-facing features described above and processed locally.

Thank you!
```

**Attachment** (optional): attach `APP_STORE_REVIEW_NOTES.md` from the repo.

---

## 9. App Privacy (Data Collection)

In App Store Connect → **App Privacy**, declare:

**Does your app collect data?** `Yes, but only data that is NOT linked to the user and NOT used for tracking.`

Actually the accurate answer for this app: **`No` — this app does not collect any data from the device.** All data (chat sessions, settings, downloaded models, tokens) stays on-device; nothing is transmitted to you or any third party for analytics.

| Data Type | Collected? | Used for | Linked to user? | Used for tracking? |
|---|---|---|---|---|
| Contact Info (email) | No | — | — | — |
| Identifiers | No | — | — | — |
| Usage Data | No | — | — | — |
| Diagnostics | No | — | — | — |
| User Content (photos, for vision prompts) | **Yes, but only ephemerally on-device** | Functionality | No | No |
| Financial/Purchases | No | — | — | — |
| Location | No | — | — | — |

> Summary text for the App Privacy label:
> ```
> Edge Mind Ai does not collect, transmit, or share any personal data. All chat content, settings, and downloaded models remain on your device. Photos and audio used in the app are processed locally for the feature you invoked and are not sent to any server. Live Web Search, when you enable it, sends only your individual search query to the third-party search provider whose API key you entered.
> ```

Required-Reason APIs (your `PrivacyInfo.xcprivacy` already declares these — they will show in App Privacy automatically):
- `UserDefaults` — for storing app settings locally.
- Disk-space / file size APIs — for model download management.

---

## 10. Screenshots (you must capture these — I can't render them)

You need screenshots from a **physical device** (MLX only runs on real hardware). Required device sizes:

**Required — iPhone 6.9" (iPhone 16 Pro Max / 17 Pro Max class):**
- 1290 × 2796 px
- Minimum 3, recommended 5–8 screenshots

**Required — iPad 13" (iPad Pro 13" M4):**
- 2064 × 2752 px
- Minimum 3 screenshots

**Suggested shot sequence (tells the privacy story):**
1. Chat screen with a streaming response + Markdown
2. Model Library — showing the curated catalog + capability badges
3. Vision prompt — photo attached with the AI describing it
4. Voice input in action (microphone active)
5. Live Search result with citation chips
6. Settings → Privacy screen

> Capture with `xcrun devicectl` or Xcode → Window → Devices and Simulators → Take Screenshot after deploying to your iPhone 17 Pro. Save as PNG/JPEG. Drag into App Store Connect.

---

## 11. Sign-in option for App Review

Because there is **no Sign in with Apple** in this build (entitlement disabled), select:
**"Sign-in type: None / No account required"**

---

## 12. Pre-submit checklist (App Store Connect will block submission until these are green)

- [ ] Build 0.1.0 (1) shows a green checkmark in TestFlight (processing finished)
- [ ] Build selected on the App Store tab → "Build" section
- [ ] All screenshots uploaded (iPhone 6.9" + iPad 13")
- [ ] Description, subtitle, keywords, promo text filled
- [ ] Support URL + Privacy Policy URL are live public links
- [ ] Copyright + category + age rating set
- [ ] Encryption attestation answered (exemption selected)
- [ ] App Review contact info + notes pasted
- [ ] App Privacy questionnaire answered (No data collected)
- [ ] Routing/Volume question answered (No)
- [ ] Export compliance answered (exempt)

Once all green → **"Add for Review"** → **"Submit to Review"**.

---

## 13. Submission command (for the NEXT version, e.g. 0.2.0)

Once 0.1.0 is in review, future uploads are one command. Bump `MARKETING_VERSION` in `project.yml`, then:

```bash
cd "/Users/vinothrajalingam/Desktop/AI_Project/ClaudeCode/Edge Mind Ai"
xcodegen generate && \
xcodebuild archive -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath build/EdgeMindAi.xcarchive -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=43NV5DTHKG CODE_SIGN_STYLE=Automatic && \
xcodebuild -exportArchive -archivePath build/EdgeMindAi.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates && \
xcrun altool --validate-app --type ios -f build/export/EdgeMindAi.ipa \
  --apiKey P86K6X54TY --apiIssuer 53d8d3d9-0cf3-419d-94f3-fe30d9115e77 && \
xcrun altool --upload-app --type ios -f build/export/EdgeMindAi.ipa \
  --apiKey P86K6X54TY --apiIssuer 53d8d3d9-0cf3-419d-94f3-fe30d9115e77
```
```

## 14. Privacy Policy — full text to host (paste into privacy.html)

```
Edge Mind Ai — Privacy Policy
Last updated: June 29, 2026

Edge Mind Ai ("the app") is built on a simple principle: your data stays on your device. This policy describes what the app does and does not do with your information.

1. What we collect
Nothing. Edge Mind Ai does not collect, transmit, sell, or share any personal data with the developer or any third party. We do not run analytics, telemetry, crash reporting, advertising, or tracking SDKs.

2. What stays on your device
• Your chat conversations and chat history
• Your app settings and system prompt
• Any AI models you choose to download
• Your optional HuggingFace access token (stored in the iOS Keychain)
• Optional local sign-in profile (display name, optional email)
All of the above are stored locally in the app's sandbox on your device and are never sent anywhere by the app.

3. Data the app processes locally for features
• Photos you attach to a chat prompt are read from your library, downsampled, and passed to an on-device vision model, then processed locally. They are not uploaded.
• Audio from voice dictation is handled by Apple's on-device speech recognition and is not sent to any server by this app.
• Face ID / Touch ID checks are performed by iOS LocalAuthentication; the app never receives or stores biometric data.

4. The only thing that leaves your device — and only when you ask
Live Web Search is OFF by default. If you turn it on (per-prompt or in Settings) and provide your own API key for Tavily, Brave Search, Serper, or a custom gateway, the app sends only your individual search query to that provider so it can return results. No other data is sent. Your use of that provider is governed by the provider's own privacy policy.

5. Model downloads
When you download a model, it is fetched directly from its source (typically Hugging Face) over HTTPS. If the model is gated, your HuggingFace token is sent only to huggingface.co to authorize the download. Model files are stored locally on your device.

6. Children
The app is rated 12+ and is not directed at children under 12. We do not knowingly collect any data from anyone, including children.

7. Third-party links
The app may display citations/links returned by an optional web search you explicitly enabled. Following a link opens it in your browser and is subject to that site's policy.

8. Your choices
You can delete any chat, model, or your local profile at any time from within the app. Uninstalling the app removes all locally stored data.

9. Changes to this policy
Material changes will be reflected by updating this page with a new date.

10. Contact
Questions: vinoth.rajalingam@icloud.com
```

---

*End of listing. Host §14 at a public URL, fill in the `[bracketed]` items, and you're ready to submit.*
