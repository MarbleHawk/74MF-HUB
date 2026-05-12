# 74mf Hub v3 — fixing the syntax error and Roblox API mistakes

## Parser error (`Expected '(' ... got ':'`)

This happens when the YouTube URL was accidentally pasted **inside** `normKey`, breaking the method chain:

**Wrong (broken):**

```lua
return (tostring(s or ""):https://www.youtube.com/@74MF_FreeScriptsgsub("%s+", ""):lower())
```

**Correct:**

```lua
return (tostring(s or ""):gsub("%s+", ""):lower())
```

The YouTube link belongs **only** in `HUB_YOUTUBE_URL` (used by the YT button), not inside `normKey`.

## Auto-fix (recommended)

1. Save your full unobfuscated hub source as e.g. `my-hub.lua` in this repo (or any path).
2. Run:

```sh
python3 scripts/fix-74mf-hub-source.py my-hub.lua -o 74mf-hub-v3-source.lua
```

This script:

- Repairs the broken `normKey` splice (`:https://...@...gsub` → `:gsub`).
- Sets `HUB_YOUTUBE_URL` to `https://www.youtube.com/@74MF_FreeScripts`.
- Replaces invalid `Instance.new("UICorner", parent).CornerRadius = ...` with a valid `do ... end` block (Roblox does not support a second argument to `Instance.new`).
- Strips accidental trailing junk lines if present.

3. Open `74mf-hub-v3-source.lua`, then run your obfuscator and replace the distributed `74MF HUB` blob.

## Manual YouTube constant

If you only change the channel link by hand:

```lua
local HUB_YOUTUBE_URL = "https://www.youtube.com/@74MF_FreeScripts"
```

Also see `dev/74mf-hub-youtube-url.lua` for the same constant in isolation.
