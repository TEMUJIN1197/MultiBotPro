# DeepSeek Harness Custom Web Extensions

This directory contains permanent Cordis plugins and feature additions developed for DeepSeek Harness (DSH):

1. **`token-meter.js` (Token Availability Meter)**:
   - Displays real-time model token availability as a percentage starting at 100% and counting down with usage.
   - Fits seamlessly onto the composer toolbar directly beside Workspace Write and Plan Mode.
   - Includes interactive hover stats and click-to-open details popover.

2. **`voice-dictation.js` (Speech-to-Text Dictation)**:
   - Adds speech-to-text dictation to the composer toolbar with a microphone icon.
   - Leverages browser Web Speech Recognition to transcribe spoken voice directly into the prompt draft in real time.
   - Features animated listening pulse and click-to-start / click-to-stop control.

3. **Prompt Edit & Revert (Built-in Chat Action)**:
   - Added an **Edit Prompt** pencil icon directly beside the **Copy** button on every user prompt bubble in the chat history.
   - **Clicking the Edit Icon**:
     1. Reverts the conversation back to that exact point in time (forking the history before that prompt, clearing away any subsequent failed turns or errors).
     2. Pre-populates the prompt input box with the exact text of that former prompt.
     3. Allows the user to immediately edit, refine, and re-run their prompt without having to re-type from scratch or carry unwanted context forward.

### Permanent Installation
All features are:
- Saved as standalone reusable Cordis plugins in `~/.dsh/plugins/` and this directory.
- Integrated directly into the core `@deepseek-ai/dsh-client-ui-conversation` and `@deepseek-ai/dsh-client-ui-chat` packages so they automatically render and function for **every session**.
