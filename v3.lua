-- 74mf Script Hub v3.0 (consolidated: panel, APIs, role-locked admin keys, case-insensitive keys)

local BOT_URL = "https://web-production-bc14.up.railway.app"

local function normKey(s)
    return (tostring(s or ""):gsub("%s+", ""):lower())
end

-- Keys are stored lowercase; matching is case-insensitive.
local ADMIN_KEYS = {
    { key = "owner-acc", name = "OWNER key" },
    { key = "mod-acc", name = "MOD key" },
    { key = "test-acc", name = "TESTER key" },
    { key = "dev-acc", name = "DEVELOPER key" },
    { key = "hm-acc", name = "HM key" },
}

local BASE_KEYS = {
    "base-access-2026",
}

local function isValidBaseKey(entered)
    local n = normKey(entered)
    for _, b in ipairs(BASE_KEYS) do
        if n == b then return true, n end
    end
    local ok, res = pcall(function()
        return game:HttpGet(BOT_URL .. "/hub/basekeyvalid?key=" .. HttpService:UrlEncode(entered))
    end)
    if ok and res and res ~= "" then
        local po, parsed = pcall(HttpService.JSONDecode, HttpService, res)
        if po and parsed and parsed.valid then return true, n end
    end
    return false, n
end

local RAYFIELD_URL = "https://sirius.menu/rayfield"
local AVG_TIME = 15
local SESSION_TTL_SEC = 24 * 60 * 60 -- must re-enter key + Discord after this (client-side)

local Rayfield = loadstring(game:HttpGet(RAYFIELD_URL))()

local hubShutdownGeneration = 0
-- DC button on login copies this invite (no key required). Edit to your real server link.
local DISCORD_INVITE_URL = "https://discord.gg/74mf"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local robloxName = LocalPlayer.Name
local accessLevel = nil
local adminName = nil
local discordUsername = nil
local sessionStart = tick()
local hubPanel = false -- Developer/Admin tab (server: panel roles or OWNER/HM admin keys)
local pendingBaseKeyLower = ""
local pendingAdminKeyLower = ""

-- ============================================================
-- SCRIPT EXECUTION LOGGER
-- ============================================================

local function logScriptExec(scriptName)
    task.spawn(function()
        local discord = discordUsername or adminName or ""
        local access = accessLevel or "unknown"
        local encodedScript = HttpService:UrlEncode(scriptName)
        local encodedRoblox = HttpService:UrlEncode(robloxName)
        local encodedDiscord = HttpService:UrlEncode(discord)
        local url = BOT_URL .. "/scriptexec?robloxname=" .. encodedRoblox .. "&discord=" .. encodedDiscord .. "&script=" .. encodedScript .. "&access=" .. access
        pcall(function()
            game:HttpGet(url)
        end)
    end)
end

-- Executor clipboard APIs vary; vanilla Roblox has none — try common globals.
local function copyToExecutorClipboard(text)
    if type(text) ~= "string" or text == "" then return false end
    local function try(fn)
        local ok, res = pcall(fn)
        return ok and res == true
    end
    if try(function()
        if typeof(setclipboard) == "function" then setclipboard(text) return true end
        return false
    end) then return true end
    if try(function()
        local g = getgenv and getgenv()
        if typeof(g) == "table" and typeof(g.setclipboard) == "function" then g.setclipboard(text) return true end
        return false
    end) then return true end
    if try(function()
        if typeof(toclipboard) == "function" then toclipboard(text) return true end
        return false
    end) then return true end
    if try(function()
        if typeof(syn) == "table" and typeof(syn.set_clipboard) == "function" then syn.set_clipboard(text) return true end
        return false
    end) then return true end
    if try(function()
        if typeof(clipboard) == "table" and typeof(clipboard.set) == "function" then clipboard.set(text) return true end
        return false
    end) then return true end
    if try(function()
        local r = getrenv and getrenv()
        if typeof(r) == "table" and typeof(r.setclipboard) == "function" then r.setclipboard(text) return true end
        return false
    end) then return true end
    return false
end

local function hubClipboardNotify(title, content, duration)
    pcall(function()
        if type(Rayfield) == "table" and Rayfield.Notify then
            Rayfield:Notify({ Title = title or "74mf Hub", Content = content or "", Duration = duration or 3 })
        end
    end)
end

local SESSION_FILE = "74mf_session_" .. robloxName .. ".txt"

local function saveSession()
    pcall(function()
        local data = HttpService:JSONEncode({
            time = os.time(),
            roblox = robloxName,
            discord = discordUsername or "",
            access = accessLevel or "base",
            admin = adminName or "",
            hubPanel = hubPanel and true or false,
        })
        writefile(SESSION_FILE, data)
    end)
end

local function loadSession()
    local parsed = nil
    pcall(function()
        if isfile and isfile(SESSION_FILE) then
            local raw = readfile(SESSION_FILE)
            local p = HttpService:JSONDecode(raw)
            if p and p.time and p.roblox == robloxName then
                if os.time() - p.time <= SESSION_TTL_SEC then
                    parsed = p
                end
            end
        end
    end)
    return parsed
end

local performHubLoginReset

local loginFlowCancelled = false

local function runLoginFlow()
loginFlowCancelled = false
local loginDoneLocal = false

-- ============================================================
-- LOGIN GUI
-- ============================================================

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Name = "74mfHubLogin"
gui.Parent = PlayerGui

-- Login frame layout (wider hub; DC/YT stay narrow fixed width)
local LOGIN_FRAME_W, LOGIN_FRAME_H = 520, 368
local LOGIN_MARGIN_X = 24
local LOGIN_BTN_W, LOGIN_BTN_GAP = 40, 6

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, LOGIN_FRAME_W, 0, LOGIN_FRAME_H)
frame.Position = UDim2.new(0.5, -LOGIN_FRAME_W / 2, 0.5, -LOGIN_FRAME_H / 2)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local closeLoginBtn = Instance.new("TextButton")
closeLoginBtn.Name = "74mfLoginClose"
closeLoginBtn.Size = UDim2.new(0, 30, 0, 30)
closeLoginBtn.Position = UDim2.new(1, -10, 0, 8)
closeLoginBtn.AnchorPoint = Vector2.new(1, 0)
closeLoginBtn.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
closeLoginBtn.BorderSizePixel = 0
closeLoginBtn.Text = "x"
closeLoginBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
closeLoginBtn.TextSize = 18
closeLoginBtn.Font = Enum.Font.GothamBold
closeLoginBtn.AutoButtonColor = true
closeLoginBtn.ZIndex = 30
Instance.new("UICorner", closeLoginBtn).CornerRadius = UDim.new(0, 6)
closeLoginBtn.Parent = frame

local function closeLoginGuiOnly()
    loginFlowCancelled = true
    loginDoneLocal = true
    pcall(function()
        gui:Destroy()
    end)
end
closeLoginBtn.MouseButton1Click:Connect(closeLoginGuiOnly)
closeLoginBtn.Activated:Connect(closeLoginGuiOnly)

local versionLbl = Instance.new("TextLabel")
versionLbl.Size = UDim2.new(1, -10, 0, 14)
versionLbl.Position = UDim2.new(0, 0, 1, -10)
versionLbl.BackgroundTransparency = 1
versionLbl.Text = "v3.0"
versionLbl.TextColor3 = Color3.fromRGB(70, 70, 70)
versionLbl.TextSize = 11
versionLbl.Font = Enum.Font.Gotham
versionLbl.TextXAlignment = Enum.TextXAlignment.Right
versionLbl.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -52, 0, 35)
title.Position = UDim2.new(0, 0, 0, 10)
title.BackgroundTransparency = 1
title.Text = "74mf Hub"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 22
title.Font = Enum.Font.GothamBold
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 40)
subtitle.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 38)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Enter your key and Discord username"
subtitle.TextColor3 = Color3.fromRGB(140, 140, 140)
subtitle.TextSize = 13
subtitle.Font = Enum.Font.Gotham
subtitle.TextWrapped = true
subtitle.Parent = frame

local keyInput = Instance.new("TextBox")
keyInput.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 36)
keyInput.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 84)
keyInput.TextEditable = true
keyInput.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
keyInput.BorderSizePixel = 0
keyInput.Text = ""
keyInput.PlaceholderText = "Enter key..."
keyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
keyInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
keyInput.TextSize = 15
keyInput.Font = Enum.Font.Gotham
keyInput.ClearTextOnFocus = false
keyInput.Parent = frame
Instance.new("UICorner", keyInput).CornerRadius = UDim.new(0, 8)

local keyErr = Instance.new("TextLabel")
keyErr.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 16)
keyErr.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 122)
keyErr.BackgroundTransparency = 1
keyErr.Text = ""
keyErr.TextColor3 = Color3.fromRGB(255, 80, 80)
keyErr.TextSize = 12
keyErr.Font = Enum.Font.Gotham
keyErr.TextXAlignment = Enum.TextXAlignment.Left
keyErr.Parent = frame

local discordInput = Instance.new("TextBox")
local discordRowRightPad = LOGIN_MARGIN_X + LOGIN_BTN_W + LOGIN_BTN_GAP + LOGIN_BTN_W
discordInput.Size = UDim2.new(1, -(LOGIN_MARGIN_X + discordRowRightPad), 0, 36)
discordInput.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 142)
discordInput.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
discordInput.BorderSizePixel = 0
discordInput.Text = ""
discordInput.PlaceholderText = "Enter Discord username..."
discordInput.TextColor3 = Color3.fromRGB(255, 255, 255)
discordInput.PlaceholderColor3 = Color3.fromRGB(60, 60, 60)
discordInput.TextSize = 15
discordInput.Font = Enum.Font.Gotham
discordInput.ClearTextOnFocus = false
discordInput.TextEditable = false
discordInput.Parent = frame
Instance.new("UICorner", discordInput).CornerRadius = UDim.new(0, 8)

local dcBtn = Instance.new("TextButton")
dcBtn.Name = "74mfCopyDiscord"
dcBtn.Size = UDim2.new(0, LOGIN_BTN_W, 0, 36)
dcBtn.Position = UDim2.new(1, -discordRowRightPad, 0, 142)
dcBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
dcBtn.BorderSizePixel = 0
dcBtn.Text = "DC"
dcBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
dcBtn.TextSize = 14
dcBtn.ZIndex = 15
dcBtn.Parent = frame
Instance.new("UICorner", dcBtn).CornerRadius = UDim.new(0, 8)

local HUB_YOUTUBE_URL = "https://www.youtube.com/channel/UC2B69nGbiNX-EcG9KaFcpVw"
local ytBtn = Instance.new("TextButton")
ytBtn.Name = "74mfCopyYoutube"
ytBtn.Size = UDim2.new(0, LOGIN_BTN_W, 0, 36)
ytBtn.Position = UDim2.new(1, -LOGIN_MARGIN_X - LOGIN_BTN_W, 0, 142)
ytBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
ytBtn.BorderSizePixel = 0
ytBtn.Text = "YT"
ytBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ytBtn.TextSize = 14
ytBtn.ZIndex = 15
ytBtn.Parent = frame
Instance.new("UICorner", ytBtn).CornerRadius = UDim.new(0, 8)

local clipNoticeToken = 0
local clipNoticeLbl = Instance.new("TextLabel")
clipNoticeLbl.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 20)
clipNoticeLbl.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 288)
clipNoticeLbl.BackgroundTransparency = 1
clipNoticeLbl.Text = ""
clipNoticeLbl.TextColor3 = Color3.fromRGB(120, 220, 160)
clipNoticeLbl.TextSize = 12
clipNoticeLbl.Font = Enum.Font.Gotham
clipNoticeLbl.TextXAlignment = Enum.TextXAlignment.Center
clipNoticeLbl.TextTransparency = 1
clipNoticeLbl.ZIndex = 50
clipNoticeLbl.Parent = frame

local function showClipboardNotice(which, customLine)
    clipNoticeToken = clipNoticeToken + 1
    local myTok = clipNoticeToken
    local label = customLine
        or (which == "youtube" and "(YouTube) copied to clipboard" or "(Discord) copied to clipboard")
    clipNoticeLbl.TextColor3 = Color3.fromRGB(120, 220, 160)
    clipNoticeLbl.Text = label
    clipNoticeLbl.TextTransparency = 0
    task.spawn(function()
        task.wait(2.5)
        if clipNoticeToken ~= myTok then return end
        for i = 0, 12 do
            if clipNoticeToken ~= myTok then return end
            clipNoticeLbl.TextTransparency = i / 12
            task.wait(0.04)
        end
        if clipNoticeToken == myTok then
            clipNoticeLbl.Text = ""
            clipNoticeLbl.TextTransparency = 1
        end
    end)
end

local lastCopyBtn = 0
local function debouncedCopy(fn)
    local t = tick()
    if t - lastCopyBtn < 0.2 then return end
    lastCopyBtn = t
    fn()
end

local function wireDcYt(btn, fn)
    local function go() debouncedCopy(fn) end
    btn.MouseButton1Click:Connect(go)
    btn.MouseButton1Down:Connect(go)
    btn.Activated:Connect(go)
end

wireDcYt(dcBtn, function()
    local ok = copyToExecutorClipboard(DISCORD_INVITE_URL)
    if ok then
        showClipboardNotice("discord", "(Discord invite) copied to clipboard")
        hubClipboardNotify("Discord", "Invite copied — paste it in your browser to join.", 4)
    else
        clipNoticeToken = clipNoticeToken + 1
        clipNoticeLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
        clipNoticeLbl.Text = "Clipboard unavailable — use an executor with setclipboard"
        clipNoticeLbl.TextTransparency = 0
        hubClipboardNotify("Discord", "Clipboard not available. Link: " .. DISCORD_INVITE_URL, 14)
        task.delay(3.5, function()
            clipNoticeLbl.Text = ""
            clipNoticeLbl.TextTransparency = 1
        end)
    end
end)

wireDcYt(ytBtn, function()
    local ok = copyToExecutorClipboard(HUB_YOUTUBE_URL)
    if ok then
        showClipboardNotice("youtube")
        hubClipboardNotify("Copied", "YouTube channel link copied.", 2)
    else
        clipNoticeToken = clipNoticeToken + 1
        clipNoticeLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
        clipNoticeLbl.Text = "Clipboard unavailable — use an executor with setclipboard"
        clipNoticeLbl.TextTransparency = 0
        hubClipboardNotify("Clipboard", "This executor has no clipboard API (setclipboard).", 4)
        task.delay(3.5, function()
            clipNoticeLbl.Text = ""
            clipNoticeLbl.TextTransparency = 1
        end)
    end
end)

local discordErr = Instance.new("TextLabel")
discordErr.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 16)
discordErr.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 180)
discordErr.BackgroundTransparency = 1
discordErr.Text = ""
discordErr.TextColor3 = Color3.fromRGB(255, 80, 80)
discordErr.TextSize = 12
discordErr.Font = Enum.Font.Gotham
discordErr.TextXAlignment = Enum.TextXAlignment.Left
discordErr.Parent = frame

local submitBtn = Instance.new("TextButton")
submitBtn.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 36)
submitBtn.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 202)
submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
submitBtn.BorderSizePixel = 0
submitBtn.Text = "Continue"
submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
submitBtn.TextSize = 15
submitBtn.Font = Enum.Font.GothamBold
submitBtn.Parent = frame
Instance.new("UICorner", submitBtn).CornerRadius = UDim.new(0, 8)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 18)
statusLbl.Position = UDim2.new(0, 0, 0, 246)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = ""
statusLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLbl.TextSize = 12
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextXAlignment = Enum.TextXAlignment.Center
statusLbl.Parent = frame

local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(1, 0, 0, 16)
timerLbl.Position = UDim2.new(0, 0, 0, 266)
timerLbl.BackgroundTransparency = 1
timerLbl.Text = ""
timerLbl.TextColor3 = Color3.fromRGB(120, 120, 120)
timerLbl.TextSize = 11
timerLbl.Font = Enum.Font.Gotham
timerLbl.TextXAlignment = Enum.TextXAlignment.Center
timerLbl.Parent = frame

-- Reparent so this label draws after status/timer (avoids being hidden under siblings).
clipNoticeLbl.Parent = frame

local function setStatus(text, color)
    statusLbl.Text = text
    statusLbl.TextColor3 = color or Color3.fromRGB(150, 150, 150)
end

local function setDiscordEnabled(enabled)
    discordInput.TextEditable = enabled
    discordInput.BackgroundColor3 = enabled and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(28, 28, 28)
    discordInput.PlaceholderColor3 = enabled and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(60, 60, 60)
end

local function shakeFrame()
    local halfW = LOGIN_FRAME_W / 2
    local halfH = LOGIN_FRAME_H / 2
    local offsets = {8, -8, 6, -6, 4, -4, 2, -2, 0}
    for _, offset in ipairs(offsets) do
        frame.Position = UDim2.new(0.5, -halfW + offset, 0.5, -halfH)
        task.wait(0.03)
    end
    frame.Position = UDim2.new(0.5, -halfW, 0.5, -halfH)
end

-- Login flow state (single submit handler — no stacked MouseButton1Click connections)
local STATE = "key"
local checking = false
local pendingAdminEntry = nil -- { key, name } after valid admin key, before /check Admin (key is lowercase)
local verifyKeyType = "Base" -- "Base" | "Admin" for /check and resend
local pendingDiscordLower = "" -- discord username (lowercase) during DM code step
local codeInputBox = nil
local resendBtn = nil
local codeChecking = false

local function destroyCodeUI()
    codeChecking = false
    if codeInputBox then codeInputBox:Destroy() codeInputBox = nil end
    if resendBtn then resendBtn:Destroy() resendBtn = nil end
    discordErr.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 180)
    submitBtn.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 202)
    keyInput.Visible = true
    keyErr.Visible = true
    discordInput.Visible = true
    dcBtn.Visible = true
    ytBtn.Visible = true
end

local function showCodeEntryUI()
    destroyCodeUI()
    keyInput.Visible = false
    keyErr.Visible = false
    discordInput.Visible = false
    dcBtn.Visible = false
    ytBtn.Visible = false
    discordErr.Text = ""
    discordErr.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 120)
    submitBtn.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 156)
    submitBtn.Text = "Submit Code"
    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)

    codeInputBox = Instance.new("TextBox")
    codeInputBox.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 36)
    codeInputBox.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 80)
    codeInputBox.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
    codeInputBox.BorderSizePixel = 0
    codeInputBox.Text = ""
    codeInputBox.PlaceholderText = "Enter 6-digit code from Discord DMs..."
    codeInputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    codeInputBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    codeInputBox.TextSize = 15
    codeInputBox.Font = Enum.Font.Gotham
    codeInputBox.ClearTextOnFocus = false
    codeInputBox.Parent = frame
    Instance.new("UICorner", codeInputBox).CornerRadius = UDim.new(0, 8)

    resendBtn = Instance.new("TextButton")
    resendBtn.Size = UDim2.new(1, -LOGIN_MARGIN_X * 2, 0, 28)
    resendBtn.Position = UDim2.new(0, LOGIN_MARGIN_X, 0, 198)
    resendBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    resendBtn.BorderSizePixel = 0
    resendBtn.Text = "Resend Code"
    resendBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    resendBtn.TextSize = 13
    resendBtn.Font = Enum.Font.Gotham
    resendBtn.Parent = frame
    Instance.new("UICorner", resendBtn).CornerRadius = UDim.new(0, 8)

    resendBtn.MouseButton1Click:Connect(function()
        resendBtn.Text = "Sending..."
        resendBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        pcall(function()
            local u = BOT_URL .. "/check?username=" .. pendingDiscordLower .. "&robloxname=" .. robloxName .. "&keytype=" .. verifyKeyType .. "&basekey=" .. HttpService:UrlEncode(pendingBaseKeyLower or "")
            if verifyKeyType == "Admin" then
                u = u .. "&adminkey=" .. HttpService:UrlEncode(pendingAdminKeyLower or "")
            end
            game:HttpGet(u)
        end)
        task.wait(1)
        resendBtn.Text = "✅ Resent!"
        task.wait(2)
        resendBtn.Text = "Resend Code"
        resendBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    end)

    STATE = "code"
end

local function finishLoginSuccess()
    setStatus("✅ Verified — loading hub...", Color3.fromRGB(0, 220, 120))
    task.wait(0.8)
    loginDoneLocal = true
    gui:Destroy()
end

local function handleCheckResponse(parsed, enteredDiscord, elapsed, isAdminFlow)
    if parsed.allowed then
        checking = false
        timerLbl.Text = ""
        submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
        discordUsername = enteredDiscord
        if parsed.hubPanel then hubPanel = true end
        if isAdminFlow or parsed.access == "admin" then
            accessLevel = "admin"
            adminName = pendingAdminEntry and pendingAdminEntry.name or "Admin"
        else
            accessLevel = "base"
        end
        finishLoginSuccess()
        return true
    end

    if parsed.reason == "pending_verification" then
        checking = false
        timerLbl.Text = ""
        submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
        setStatus("✅ Code sent to your Discord DMs!", Color3.fromRGB(0, 220, 120))
        pendingDiscordLower = enteredDiscord
        showCodeEntryUI()
        return true
    end

    checking = false
    timerLbl.Text = ""
    submitBtn.Text = "Verify & Continue"
    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
    setStatus("", nil)
    task.spawn(shakeFrame)

    if parsed.reason == "dm_failed" then
        discordErr.Text = "Could not DM you. Open DMs from server members, or ask an admin."
    elseif parsed.reason == "wrong_role_for_key" then
        discordErr.Text = "Your Discord role does not match that key (e.g. TEST-ACC only with Tester role)."
    elseif parsed.reason == "invalid_adminkey" then
        discordErr.Text = "Hub is out of date or key type missing — re-download the hub script."
    elseif parsed.reason == "not_on_admin_list" then
        discordErr.Text = "Your Discord is not on the staff list for admin keys."
    elseif parsed.reason == "not in server" then
        discordErr.Text = "You are not in the Discord server."
    elseif parsed.reason == "blacklisted" then
        discordErr.Text = "You are blacklisted from this hub."
    elseif parsed.reason == "account_locked" then
        discordErr.Text = "This Roblox account is linked to a different Discord. Open a ticket."
    elseif parsed.reason == "invalid_base_key" then
        discordErr.Text = "That base key is not valid on the server. Ask staff to add it or fix spelling."
    else
        discordErr.Text = "Verification failed. Try again."
    end
    return true
end

submitBtn.MouseButton1Click:Connect(function()
    if checking or codeChecking then return end

    if STATE == "code" then
        if not codeInputBox then return end
        local codeEntered = codeInputBox.Text:gsub("%s+", "")
        if codeEntered == "" then
            discordErr.Text = "Code field is empty."
            task.spawn(shakeFrame)
            return
        end
        if #codeEntered ~= 6 then
            discordErr.Text = "Code must be 6 digits."
            task.spawn(shakeFrame)
            return
        end
        codeChecking = true
        discordErr.Text = ""
        submitBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        setStatus("Verifying code...", Color3.fromRGB(150, 200, 255))
        task.spawn(function()
            local cOk, cResult = pcall(function()
                local vu = BOT_URL .. "/verify?code=" .. codeEntered .. "&robloxname=" .. robloxName
                if verifyKeyType == "Admin" then
                    vu = vu .. "&adminkey=" .. HttpService:UrlEncode(pendingAdminKeyLower or "")
                end
                return game:HttpGet(vu)
            end)
            codeChecking = false
            submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
            if cOk and cResult and cResult ~= "" then
                local cParseOk, cParsed = pcall(HttpService.JSONDecode, HttpService, cResult)
                if cParseOk and cParsed and cParsed.success then
                    discordUsername = pendingDiscordLower
                    if verifyKeyType == "Admin" then
                        accessLevel = "admin"
                        adminName = pendingAdminEntry and pendingAdminEntry.name or "Admin"
                    else
                        accessLevel = "base"
                    end
                    if cParsed.hubPanel then hubPanel = true end
                    finishLoginSuccess()
                else
                    task.spawn(shakeFrame)
                    local reason = cParsed and cParsed.reason or ""
                    if reason == "wrong_role_for_key" then
                        discordErr.Text = "Your Discord role does not match that admin key."
                    elseif reason == "invalid_adminkey" or reason == "adminkey_mismatch" then
                        discordErr.Text = "Key mismatch — restart login with the same admin key you requested the code with."
                    elseif reason:find("expired") then
                        discordErr.Text = "Code expired. Click Resend Code."
                    elseif reason:find("Invalid") or reason:find("does not match") then
                        discordErr.Text = "Incorrect code. Try again."
                    else
                        discordErr.Text = "Verification failed. Try again."
                    end
                    setStatus("", nil)
                end
            else
                task.spawn(shakeFrame)
                discordErr.Text = "Could not connect to server. Try again."
                setStatus("", nil)
            end
        end)
        return
    end

    if STATE == "key" then
        local entered = keyInput.Text:gsub("%s+", "")
        if entered == "" then
            keyErr.Text = "Key field is empty."
            task.spawn(shakeFrame)
            return
        end

        for _, entry in ipairs(ADMIN_KEYS) do
            if normKey(entered) == entry.key then
                pendingAdminEntry = entry
                pendingAdminKeyLower = entry.key
                keyErr.Text = ""
                setDiscordEnabled(true)
                subtitle.Text = "Admin key: enter your Discord — you can edit the key above if you picked the wrong one. Role must match the key."
                setStatus("Key accepted — enter Discord, then verify.", Color3.fromRGB(0, 200, 120))
                submitBtn.Text = "Verify & Continue"
                STATE = "admin_discord"
                return
            end
        end

        local okBase, canonBase = isValidBaseKey(entered)
        if okBase then
            accessLevel = "base"
            pendingAdminEntry = nil
            pendingBaseKeyLower = canonBase
            keyErr.Text = ""
            setStatus("✅ Key accepted — enter your Discord username", Color3.fromRGB(0, 220, 120))
            setDiscordEnabled(true)
            verifyKeyType = "Base"
            subtitle.Text = "Enter your key and Discord username"
            STATE = "discord"
            submitBtn.Text = "Verify & Continue"
            return
        end

        keyErr.Text = "Invalid key. Try again."
        task.spawn(shakeFrame)
        pcall(function()
            game:HttpGet(BOT_URL .. "/wrongkey?robloxname=" .. robloxName)
        end)
        return
    end

    if STATE == "admin_discord" then
        local keyRaw = keyInput.Text:gsub("%s+", "")
        if keyRaw == "" then
            keyErr.Text = "Key field is empty."
            discordErr.Text = ""
            task.spawn(shakeFrame)
            return
        end

        -- Allow switching from admin to base key without restarting the whole flow
        local okBaseSwitch, canonBaseSwitch = isValidBaseKey(keyRaw)
        if okBaseSwitch then
            pendingAdminEntry = nil
            pendingAdminKeyLower = ""
            pendingBaseKeyLower = canonBaseSwitch
            accessLevel = "base"
            verifyKeyType = "Base"
            STATE = "discord"
            subtitle.Text = "Enter your key and Discord username"
            setStatus("✅ Key accepted — enter your Discord username", Color3.fromRGB(0, 220, 120))
            keyErr.Text = ""
            discordErr.Text = ""
            submitBtn.Text = "Verify & Continue"
            return
        end

        local matchedAdmin = nil
        for _, entry in ipairs(ADMIN_KEYS) do
            if normKey(keyRaw) == entry.key then
                matchedAdmin = entry
                break
            end
        end
        if not matchedAdmin then
            keyErr.Text = "Invalid admin key — fix the top field or use a base key."
            discordErr.Text = ""
            task.spawn(shakeFrame)
            return
        end
        pendingAdminEntry = matchedAdmin
        pendingAdminKeyLower = matchedAdmin.key
        keyErr.Text = ""

        local entered = discordInput.Text:gsub("%s+", ""):lower()
        if entered == "" then
            discordErr.Text = "Discord username field is empty."
            task.spawn(shakeFrame)
            return
        end
        verifyKeyType = "Admin"
        checking = true
        discordErr.Text = ""
        submitBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        timerLbl.Text = ""
        local startTime = tick()

        task.spawn(function()
            local dots = {".", "..", "..."}
            local d = 1
            while checking do
                task.wait(0.4)
                local elapsed = math.floor(tick() - startTime)
                local eta = math.max(0, AVG_TIME - elapsed)
                statusLbl.Text = "Verifying Discord (admin)" .. dots[d]
                statusLbl.TextColor3 = Color3.fromRGB(150, 200, 255)
                d = d % 3 + 1
                if elapsed < AVG_TIME then
                    timerLbl.Text = string.format("⏱ %ds elapsed  •  ETA ~%ds  •  avg ~%ds", elapsed, eta, AVG_TIME)
                    timerLbl.TextColor3 = Color3.fromRGB(150, 200, 150)
                else
                    timerLbl.Text = string.format("⏱ %ds elapsed  •  still waiting... (avg ~%ds)", elapsed, AVG_TIME)
                    timerLbl.TextColor3 = Color3.fromRGB(255, 180, 80)
                end
            end
        end)

        task.spawn(function()
            local ok, result = pcall(function()
                return game:HttpGet(BOT_URL .. "/check?username=" .. entered .. "&robloxname=" .. robloxName .. "&keytype=Admin&adminkey=" .. HttpService:UrlEncode(pendingAdminKeyLower or ""))
            end)
            local elapsed = math.floor(tick() - startTime)
            checking = false
            timerLbl.Text = ""
            if ok and result and result ~= "" then
                local parseOk, parsed = pcall(HttpService.JSONDecode, HttpService, result)
                if parseOk and parsed then
                    handleCheckResponse(parsed, entered, elapsed, true)
                else
                    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
                    discordErr.Text = "Bad response from server. Try again."
                    setStatus("", nil)
                    task.spawn(shakeFrame)
                end
            else
                submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
                discordErr.Text = string.format("Could not connect to server. Try again. (%ds)", elapsed)
                setStatus("", nil)
                task.spawn(shakeFrame)
            end
        end)
        return
    end

    if STATE == "discord" then
        local entered = discordInput.Text:gsub("%s+", ""):lower()
        if entered == "" then
            discordErr.Text = "Discord username field is empty."
            task.spawn(shakeFrame)
            return
        end

        verifyKeyType = "Base"
        checking = true
        discordErr.Text = ""
        submitBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        timerLbl.Text = ""

        local startTime = tick()

        task.spawn(function()
            local dots = {".", "..", "..."}
            local d = 1
            while checking do
                task.wait(0.4)
                local elapsed = math.floor(tick() - startTime)
                local eta = math.max(0, AVG_TIME - elapsed)
                statusLbl.Text = "Verifying Discord" .. dots[d]
                statusLbl.TextColor3 = Color3.fromRGB(150, 200, 255)
                d = d % 3 + 1
                if elapsed < AVG_TIME then
                    timerLbl.Text = string.format("⏱ %ds elapsed  •  ETA ~%ds  •  avg ~%ds", elapsed, eta, AVG_TIME)
                    timerLbl.TextColor3 = Color3.fromRGB(150, 200, 150)
                else
                    timerLbl.Text = string.format("⏱ %ds elapsed  •  still waiting... (avg ~%ds)", elapsed, AVG_TIME)
                    timerLbl.TextColor3 = Color3.fromRGB(255, 180, 80)
                end
            end
        end)

        task.spawn(function()
            local ok, result = pcall(function()
                return game:HttpGet(BOT_URL .. "/check?username=" .. entered .. "&robloxname=" .. robloxName .. "&keytype=Base&basekey=" .. HttpService:UrlEncode(pendingBaseKeyLower or ""))
            end)

            local elapsed = math.floor(tick() - startTime)
            checking = false
            timerLbl.Text = ""

            if ok and result and result ~= "" then
                local parseOk, parsed = pcall(HttpService.JSONDecode, HttpService, result)
                if parseOk and parsed then
                    if parsed.allowed then
                        discordUsername = entered
                        accessLevel = "base"
                        adminName = nil
                        if parsed.hubPanel then hubPanel = true end
                        finishLoginSuccess()
                    elseif parsed.reason == "pending_verification" then
                        setStatus("✅ Code sent to your Discord DMs!", Color3.fromRGB(0, 220, 120))
                        submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
                        pendingDiscordLower = entered
                        showCodeEntryUI()
                    else
                        handleCheckResponse(parsed, entered, elapsed, false)
                    end
                else
                    submitBtn.Text = "Verify & Continue"
                    submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
                    discordErr.Text = "Bad response from server. Try again."
                    setStatus("", nil)
                    task.spawn(shakeFrame)
                end
            else
                submitBtn.Text = "Verify & Continue"
                submitBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
                discordErr.Text = string.format("Could not connect to server. Try again. (%ds)", elapsed)
                setStatus("", nil)
                task.spawn(shakeFrame)
            end
        end)
    end
end)

local savedSession = loadSession()
if savedSession then
    accessLevel = savedSession.access
    discordUsername = savedSession.discord ~= "" and savedSession.discord or nil
    adminName = savedSession.admin ~= "" and savedSession.admin or nil
    hubPanel = savedSession.hubPanel == true
    loginDoneLocal = true
    gui:Destroy()
end

repeat task.wait(0.1) until loginDoneLocal
end

local function startHubMain()
local myHubGen = hubShutdownGeneration

saveSession()

sessionStart = tick()

task.spawn(function()
    local discordParam = HttpService:UrlEncode(discordUsername or adminName or "")
    local accessParam = accessLevel or "base"
    pcall(function()
        game:HttpGet(BOT_URL .. "/hubexec?robloxname=" .. HttpService:UrlEncode(robloxName) .. "&discord=" .. discordParam .. "&access=" .. accessParam)
    end)
end)

pcall(function()
    local dc = discordUsername or ""
    local r = game:HttpGet(BOT_URL .. "/hubsync?discord=" .. HttpService:UrlEncode(dc) .. "&robloxname=" .. HttpService:UrlEncode(robloxName))
    local p = HttpService:JSONDecode(r)
    if p and p.hubPanel then hubPanel = true end
end)

local function formatCountdown(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    else
        return string.format("%dm %ds", m, s)
    end
end

local hubTitle = accessLevel == "admin" and ("74mf Hub | ADMIN - " .. adminName) or "74mf Hub | BASIC ACCESS"

local Window = Rayfield:CreateWindow({
    Name = hubTitle,
    LoadingTitle = "74mf Script Hub",
    LoadingSubtitle = "by 74mf",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
    DisableRayfieldPrompts = true,
    Toggle = {
        Enabled = true,
        Keybind = "L"
    }
})

local function getSessionTime()
    local elapsed = math.floor(tick() - sessionStart)
    local mins = math.floor(elapsed / 60)
    local secs = elapsed % 60
    return string.format("%dm %ds", mins, secs)
end

-- HOME TAB
local InfoTab = Window:CreateTab("🏠 Home", 0)

InfoTab:CreateSection("👋 Welcome")
local displayName = LocalPlayer.DisplayName ~= LocalPlayer.Name and LocalPlayer.DisplayName or LocalPlayer.Name
InfoTab:CreateLabel("Welcome, " .. displayName .. "!")
local clockLabel = InfoTab:CreateLabel("Local Time: --:--:--")
task.spawn(function()
    while true do
        task.wait(1)
        if myHubGen ~= hubShutdownGeneration then return end
        pcall(function()
            local t = os.date("*t")
            local h, m, s = t.hour, t.min, t.sec
            local ampm = h >= 12 and "PM" or "AM"
            h = h % 12
            if h == 0 then h = 12 end
            clockLabel:Set(string.format("Local Time: %d:%02d:%02d %s", h, m, s, ampm))
        end)
    end
end)

InfoTab:CreateSection("📢 Weekly Update")
InfoTab:CreateParagraph({Title = "This Week", Content = "- v3.0: One release — in-hub Admin tab (panel roles / OWNER / HM), remote hub tools\n- Admin keys locked to Discord roles (e.g. TEST-ACC only with Tester)\n- Case-insensitive keys; dynamic base keys; live banner + broadcast; 24h session"})

InfoTab:CreateSection("📌 Live notice")
local homeBannerLabel = InfoTab:CreateLabel("(no banner — panel can set one)")

InfoTab:CreateSection("📋 About")
InfoTab:CreateLabel("Hub: 74mf Script Hub  •  v3.0")
InfoTab:CreateLabel("We want everyone to use safe, tested scripts. This hub uses a key system to ensure scripts are checked and trusted.")

InfoTab:CreateButton({
    Name = "Copy Discord server invite (no hub key needed)",
    Callback = function()
        if copyToExecutorClipboard(DISCORD_INVITE_URL) then
            Rayfield:Notify({ Title = "Discord", Content = "Invite copied — paste it in your browser to join the server.", Duration = 5 })
        else
            Rayfield:Notify({ Title = "Discord invite", Content = DISCORD_INVITE_URL, Duration = 16 })
        end
    end,
})

if accessLevel == "admin" then
    InfoTab:CreateLabel("Access Level: ADMIN  •  Logged in as: " .. adminName)
    InfoTab:CreateLabel("Roblox: " .. robloxName)
else
    InfoTab:CreateLabel("Access Level: BASIC  •  Discord: " .. (discordUsername or "unknown"))
    InfoTab:CreateLabel("Roblox: " .. robloxName)
end

InfoTab:CreateButton({
    Name = "My Teams Inspo Script - Silent X",
    Callback = function()
        logScriptExec("Silent X")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-Silent-X-206984"))()
    end
})

InfoTab:CreateSection("⏱ Session")
local sessionLabel = InfoTab:CreateLabel("Session Time: " .. getSessionTime())

task.spawn(function()
    while task.wait(1) do
        if myHubGen ~= hubShutdownGeneration then return end
        pcall(function()
            sessionLabel:Set("Session Time: " .. getSessionTime())
        end)
    end
end)

task.spawn(function()
    local ok, result = pcall(function()
        return game:HttpGet(BOT_URL .. "/streak?robloxname=" .. robloxName)
    end)
    if ok and result and result ~= "" then
        local parseOk, parsed = pcall(HttpService.JSONDecode, HttpService, result)
        if parseOk and parsed and parsed.streak then
            pcall(function()
                InfoTab:CreateLabel("Login Streak: " .. parsed.streak .. " day(s) 🔥")
            end)
        end
    end
end)

local lastHubBroadcast = ""
task.spawn(function()
    while task.wait(12) do
        if myHubGen ~= hubShutdownGeneration then return end
        pcall(function()
            local dc = discordUsername or ""
            local url = BOT_URL .. "/hubsync?discord=" .. HttpService:UrlEncode(dc) .. "&robloxname=" .. HttpService:UrlEncode(robloxName)
            local r = game:HttpGet(url)
            local p = HttpService:JSONDecode(r)
            if not p then return end
            if p.hubPanel then hubPanel = true end
            if p.homeBanner and p.homeBanner ~= "" then
                homeBannerLabel:Set("📌 " .. tostring(p.homeBanner))
            end
            if p.broadcast and p.broadcast ~= "" and p.broadcast ~= lastHubBroadcast then
                lastHubBroadcast = p.broadcast
                Rayfield:Notify({ Title = "Hub broadcast", Content = tostring(p.broadcast), Duration = 14 })
            end
            if p.forceRelogin then
                pcall(function()
                    if isfile and isfile(SESSION_FILE) then
                        delfile(SESSION_FILE)
                    end
                end)
                Rayfield:Notify({ Title = "Session ended", Content = "Staff forced re-login. Logging you out…", Duration = 4 })
                task.spawn(function()
                    task.wait(0.5)
                    performHubLoginReset()
                end)
            end
        end)
    end
end)
-- SERVER TAB
local ServerTab = Window:CreateTab("🖥️ Server", 0)

ServerTab:CreateSection("⚡ Quick Actions")
ServerTab:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        local placeId = game.PlaceId
        local jobId = game.JobId
        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, jobId)
    end
})
ServerTab:CreateButton({
    Name = "Join Small Server",
    Callback = function()
        local TeleportService = game:GetService("TeleportService")
        local HttpService = game:GetService("HttpService")
        local placeId = game.PlaceId
        local ok, servers = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if ok and servers and servers.data then
            local smallest = nil
            for _, s in ipairs(servers.data) do
                if s.id ~= game.JobId then
                    if not smallest or s.playing < smallest.playing then
                        smallest = s
                    end
                end
            end
            if smallest then
                TeleportService:TeleportToPlaceInstance(placeId, smallest.id)
            else
                Rayfield:Notify({ Title = "No Server Found", Content = "Could not find a smaller server.", Duration = 3 })
            end
        else
            Rayfield:Notify({ Title = "Error", Content = "Failed to fetch server list.", Duration = 3 })
        end
    end
})
ServerTab:CreateButton({
    Name = "Server Hop",
    Callback = function()
        local TeleportService = game:GetService("TeleportService")
        local HttpService = game:GetService("HttpService")
        local placeId = game.PlaceId
        local ok, servers = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"))
        end)
        if ok and servers and servers.data then
            for _, s in ipairs(servers.data) do
                if s.id ~= game.JobId then
                    TeleportService:TeleportToPlaceInstance(placeId, s.id)
                    return
                end
            end
            Rayfield:Notify({ Title = "No Server Found", Content = "Could not find another server.", Duration = 3 })
        else
            Rayfield:Notify({ Title = "Error", Content = "Failed to fetch server list.", Duration = 3 })
        end
    end
})

ServerTab:CreateSection("🖥 Server Info")
local gameLbl = ServerTab:CreateLabel("Game: Loading...")
local playersLbl = ServerTab:CreateLabel("Players: Loading...")
local placeIdLbl = ServerTab:CreateLabel("Place ID: Loading...")
local gameIdLbl = ServerTab:CreateLabel("Game ID: Loading...")
local jobIdLbl = ServerTab:CreateLabel("Job ID: Loading...")
local serverLinkLbl = ServerTab:CreateLabel("Server Link: Loading...")

task.spawn(function()
    pcall(function()
        local placeId = game.PlaceId
        local gameId = game.GameId
        local jobId = game.JobId
        local maxPlayers = game:GetService("Players").MaxPlayers
        local gameName = "Unknown"
        pcall(function() gameName = game:GetService("MarketplaceService"):GetProductInfo(placeId).Name end)
        pcall(function() gameLbl:Set("Game: " .. tostring(gameName)) end)
        pcall(function() placeIdLbl:Set("Place ID: " .. tostring(placeId)) end)
        pcall(function() gameIdLbl:Set("Game ID: " .. tostring(gameId)) end)
        pcall(function() jobIdLbl:Set("Job ID: " .. tostring(jobId)) end)
        pcall(function() serverLinkLbl:Set("Server Link: READY") end)
        while true do
            task.wait(5)
            if myHubGen ~= hubShutdownGeneration then return end
            local playerCount = #game:GetService("Players"):GetPlayers()
            pcall(function() playersLbl:Set("Players: " .. playerCount .. "/" .. maxPlayers) end)
        end
    end)
end)

ServerTab:CreateSection("📋 Copy Info")
ServerTab:CreateButton({
    Name = "Copy Place ID",
    Callback = function()
        pcall(function() setclipboard(tostring(game.PlaceId)) end)
        Rayfield:Notify({ Title = "Copied!", Content = "Place ID copied to clipboard.", Duration = 3 })
    end
})
ServerTab:CreateButton({
    Name = "Copy Game ID",
    Callback = function()
        pcall(function() setclipboard(tostring(game.GameId)) end)
        Rayfield:Notify({ Title = "Copied!", Content = "Game ID copied to clipboard.", Duration = 3 })
    end
})
ServerTab:CreateButton({
    Name = "Copy Job ID",
    Callback = function()
        pcall(function() setclipboard(tostring(game.JobId)) end)
        Rayfield:Notify({ Title = "Copied!", Content = "Job ID copied to clipboard.", Duration = 3 })
    end
})
ServerTab:CreateButton({
    Name = "Copy Server Link",
    Callback = function()
        pcall(function()
            local link = "roblox://experiences/start?placeId=" .. game.PlaceId .. "&gameInstanceId=" .. game.JobId
            setclipboard(link)
        end)
        Rayfield:Notify({ Title = "Copied!", Content = "Server link copied to clipboard.", Duration = 3 })
    end
})
-- SCRIPTS TAB
local ScriptTab = Window:CreateTab("📜 Scripts", 0)

-- ============================================================
-- CUSTOM SCRIPTS SAVE/LOAD
-- ============================================================
local CUSTOM_SCRIPTS_FILE = "74mf_custom_scripts_" .. robloxName .. ".txt"

local function loadCustomScripts()
    local result = {}
    pcall(function()
        if isfile and isfile(CUSTOM_SCRIPTS_FILE) then
            local raw = readfile(CUSTOM_SCRIPTS_FILE)
            local parsed = HttpService:JSONDecode(raw)
            if parsed and type(parsed) == "table" then
                result = parsed
            end
        end
    end)
    return result
end

local function saveCustomScripts(list)
    pcall(function()
        writefile(CUSTOM_SCRIPTS_FILE, HttpService:JSONEncode(list))
    end)
end

local customScriptsList = loadCustomScripts()

local function createCustomButton(entry)
    ScriptTab:CreateButton({
        Name = "▶ " .. entry.name,
        Callback = function()
            logScriptExec("Custom: " .. entry.name)
            local ok, err = pcall(loadstring(entry.script))
            if not ok then
                Rayfield:Notify({ Title = "Script Error", Content = tostring(err), Duration = 5 })
            end
        end,
    })
end

ScriptTab:CreateSection("Arsenal")
ScriptTab:CreateButton({
    Name = "Run - Arsenal",
    Callback = function()
        logScriptExec("Arsenal")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Arsenal-Thunder-Client-For-Solara-13092"))()
    end
})

ScriptTab:CreateSection("Beat Up Gubby in His Own Home")
ScriptTab:CreateButton({
    Name = "Run - Beat Up Gubby in His Own Home",
    Callback = function()
        logScriptExec("Beat Up Gubby in His Own Home")
        local args = {
            [1] = -math.huge
        }
        game:GetService("ReplicatedStorage").Networking.Server.RemoteEvents.PurchaseGas:FireServer(unpack(args))
    end
})

ScriptTab:CreateSection("Blade Ball")
ScriptTab:CreateButton({
    Name = "Run - Blade Ball",
    Callback = function()
        logScriptExec("Blade Ball")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Akash1al/Blade-Ball-Updated-Script/refs/heads/main/Blade-Ball-Script"))()
    end
})

ScriptTab:CreateSection("Breaking Point")
ScriptTab:CreateButton({
    Name = "Run - Breaking Plus",
    Callback = function()
        logScriptExec("Breaking Point - Breaking Plus")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/NaikoScript/Breaking-Plus/main/Script"))("Log")
    end
})

ScriptTab:CreateSection("Bee Swarm Simulator")
ScriptTab:CreateButton({
    Name = "Run - Kron Hub - Bee Swarm",
    Callback = function()
        logScriptExec("Bee Swarm Simulator - Kron Hub")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Bee-Swarm-Simulator-Kron-Hub-20936"))()
    end
})

ScriptTab:CreateSection("Collect All Pets")
ScriptTab:CreateButton({
    Name = "Run - Collect All Pets - by 74MF",
    Callback = function()
        logScriptExec("Collect All Pets")
        loadstring(game:HttpGet("https://pastebin.com/raw/jPshhynX"))()
    end
})

ScriptTab:CreateSection("Dead Rails")
ScriptTab:CreateButton({
    Name = "Run - Dead Rails",
    Callback = function()
        logScriptExec("Dead Rails")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/ergerg4/bitenights.github.io/refs/heads/main/ringta.lua"))()
    end
})

ScriptTab:CreateSection("Dive Down")
ScriptTab:CreateButton({
    Name = "Run - Dive Down Inf Money",
    Callback = function()
        logScriptExec("Dive Down - Inf Money")
        loadstring(game:HttpGet("https://pastebin.com/raw/hWESxshL"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Dive Down No Drown",
    Callback = function()
        logScriptExec("Dive Down - No Drown")
        loadstring(game:HttpGet("https://pastebin.com/raw/kYNQfh9J"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Bhub Remastered",
    Callback = function()
        logScriptExec("Dive Down - Bhub Remastered")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/bo-xd/Bhub-remastered/main/src/main.lua"))()
    end
})

ScriptTab:CreateSection("Evade")
ScriptTab:CreateButton({
    Name = "Run - Bhub Remastered",
    Callback = function()
        logScriptExec("Evade - Bhub Remastered")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/bo-xd/Bhub-remastered/main/src/main.lua"))()
    end
})

ScriptTab:CreateSection("Egg Farm Simulator")
ScriptTab:CreateButton({
    Name = "Run - Egg Farm Simulator",
    Callback = function()
        logScriptExec("Egg Farm Simulator")
        loadstring(game:HttpGet("https://ibin.site/raw/1zre8ytq", true))()
    end
})

ScriptTab:CreateSection("FIFA World Soccer")
ScriptTab:CreateButton({
    Name = "Run - FIFA World Soccer",
    Callback = function()
        logScriptExec("FIFA World Soccer")
        loadstring(game:HttpGet("https://rawscripts.net/raw/FIFA-Super-Soccer!-sportsclub-FIFA-Super-Soccer-Script-all-executors-supported-240556"))()
    end
})

ScriptTab:CreateSection("Hub")
ScriptTab:CreateButton({
    Name = "Run - Homohack Hub",
    Callback = function()
        logScriptExec("Hub - Homohack Hub")
        loadstring(game:HttpGet("https://pastebin.com/raw/Nu80dqha"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Molyn Hub",
    Callback = function()
        logScriptExec("Hub - Molyn Hub")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-MOLYN-DEVELOPMENT-201480"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Script Hub X Multi Game Aimbot",
    Callback = function()
        logScriptExec("Hub - Script Hub X")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-Script-Hub-X-158195"))()
    end
})

ScriptTab:CreateSection("Infectious Smile")
ScriptTab:CreateButton({
    Name = "Run - Infectious Smile",
    Callback = function()
        logScriptExec("Infectious Smile")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Infectious-Smile-Esp-for-90024"))()
    end
})

ScriptTab:CreateSection("Kick a Lucky Block")
ScriptTab:CreateButton({
    Name = "Run - Kick a Lucky Block",
    Callback = function()
        logScriptExec("Kick a Lucky Block")
        loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/bf5bd435930dfdca3f26835bffca3fba.lua"))()
    end
})

ScriptTab:CreateSection("Long Jump Difficulty Chart")
ScriptTab:CreateButton({
    Name = "Run - Long Jump Difficulty Chart",
    Callback = function()
        logScriptExec("Long Jump Difficulty Chart")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Stud-Long-Jump-Per-Difficulty-Chart-Obby-Infinite-Coins-208207"))()
    end
})

ScriptTab:CreateSection("Murderers vs Sheriffs")
ScriptTab:CreateButton({
    Name = "Run - Murderers vs Sheriffs - by 74MF",
    Callback = function()
        logScriptExec("Murderers vs Sheriffs")
        loadstring(game:HttpGet("https://pastebin.com/raw/6sSqX9Wp"))()
    end
})

ScriptTab:CreateSection("Natural Disaster Survival")
ScriptTab:CreateButton({
    Name = "Run - Natural Disaster Survival - by 74MF",
    Callback = function()
        logScriptExec("Natural Disaster Survival")
        loadstring(game:HttpGet("https://pastebin.com/raw/jeuXWU3u"))()
    end
})

ScriptTab:CreateSection("Operation Siege")
ScriptTab:CreateButton({
    Name = "Run - Operation Siege",
    Callback = function()
        logScriptExec("Operation Siege")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Operations:-Siege-NO-KEY-KILL-ALL-INF-AMMO-WALLBANG-206094"))()
    end
})

ScriptTab:CreateSection("Playground Basketball")
ScriptTab:CreateButton({
    Name = "Run - Playground Basketball",
    Callback = function()
        logScriptExec("Playground Basketball")
        loadstring(game:HttpGet("https://scripts.getascendify.lol/sportsclub.luau"))()
    end
})

ScriptTab:CreateSection("Summon Heroes")
ScriptTab:CreateButton({
    Name = "Run - Summon Heroes",
    Callback = function()
        logScriptExec("Summon Heroes")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/robcatservice/scripts/refs/heads/main/SummonHeroes.lua"))()
    end
})

ScriptTab:CreateSection("Sword Factory")
ScriptTab:CreateButton({
    Name = "Run - Sword Factory PC - by 74MF",
    Callback = function()
        logScriptExec("Sword Factory PC")
        task.delay(0.1, function()
            loadstring(game:HttpGet("https://pastebin.com/raw/e7irmq6m"))()
        end)
    end
})
ScriptTab:CreateButton({
    Name = "Run - Sword Factory Mobile - by 74MF",
    Callback = function()
        logScriptExec("Sword Factory Mobile")
        loadstring(game:HttpGet("https://pastebin.com/raw/EeB0YFaE"))()
    end
})

ScriptTab:CreateSection("Tower of Hell")
ScriptTab:CreateButton({
    Name = "Run - Tower of Hell",
    Callback = function()
        logScriptExec("Tower of Hell")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Tower-of-Hell-Koala-Scripts-27478"))()
    end
})

ScriptTab:CreateSection("Unbox A Factory")
ScriptTab:CreateButton({
    Name = "Run - Unbox A Factory - by 74MF",
    Callback = function()
        logScriptExec("Unbox A Factory")
        loadstring(game:HttpGet("https://pastebin.com/raw/BYxDhPYu"))()
    end
})

ScriptTab:CreateSection("Universal")
ScriptTab:CreateButton({
    Name = "Run - Universal Aimbot - by 74MF",
    Callback = function()
        logScriptExec("Universal Aimbot")
        loadstring(game:HttpGet("https://pastebin.com/raw/5T3T3sNe"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Universal Movement ESP - by 74MF",
    Callback = function()
        logScriptExec("Universal Movement ESP")
        loadstring(game:HttpGet("https://pastebin.com/raw/zyQrj3ni"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Freecam",
    Callback = function()
        logScriptExec("Universal - Freecam")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/quocthaioppoa9-create/Free-cam-script/refs/heads/main/script.lua"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Universal Decompiler",
    Callback = function()
        logScriptExec("Universal - Decompiler")
        loadstring(game:HttpGet("https://pastebin.com/raw/Gf9xZPx7"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Dex++",
    Callback = function()
        logScriptExec("Universal - Dex++")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/jodta/my-scripts/refs/heads/main/Dex%2B%2B/Decompiler%20Fix.lua"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Infinite Yield",
    Callback = function()
        logScriptExec("Universal - Infinite Yield")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Vexro Emote Player 40K+",
    Callback = function()
        logScriptExec("Universal - Vexro Emotes")
        loadstring(game:HttpGet("https://raw.githubusercontent.com/zyrovell/Vexro/main/vexroemotes.lua"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Kawatan Hub",
    Callback = function()
        logScriptExec("Universal - Kawatan Hub")
        loadstring(game:HttpGet('https://pastebin.com/raw/irdeECyj'))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Music Pack",
    Callback = function()
        logScriptExec("Universal - Music Pack")
        loadstring(game:HttpGet('https://pastefy.app/G78PfjdT/raw'))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - NPC ESP",
    Callback = function()
        logScriptExec("Universal - NPC ESP")
        loadstring(game:HttpGet("https://pastebin.com/raw/YY6mLDtY"))()
    end
})
ScriptTab:CreateButton({
    Name = "Run - Fly",
    Callback = function()
        logScriptExec("Universal - Fly")
        loadstring(game:HttpGet("https://pastefy.app/9bilwWLP/raw"))()
    end
})

ScriptTab:CreateSection("Westbound")
ScriptTab:CreateButton({
    Name = "Run - Westbound",
    Callback = function()
        logScriptExec("Westbound")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Westbound-OVERLORD-KEYLESS-136348"))()
    end
})

ScriptTab:CreateSection("World Fighters")
ScriptTab:CreateButton({
    Name = "Run - Voxle - World Fighters",
    Callback = function()
        logScriptExec("World Fighters - Voxle")
        loadstring(game:HttpGet("https://pastebin.com/raw/BHR35n2b"))()
    end
})

ScriptTab:CreateSection("Zombie Attack")
ScriptTab:CreateButton({
    Name = "Run - Zombie Attack",
    Callback = function()
        logScriptExec("Zombie Attack")
        loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-Zombie-Script-135159"))()
    end
})

ScriptTab:CreateDivider()
ScriptTab:CreateSection("⭐ Custom Scripts")
local function getCustomScriptNames()
    local names = {}
    for _, entry in ipairs(customScriptsList) do
        table.insert(names, entry.name)
    end
    if #names == 0 then
        table.insert(names, "No scripts saved")
    end
    return names
end

local selectedCustomScript = ""
local customDropdown = ScriptTab:CreateDropdown({
    Name = "Saved Custom Scripts",
    Options = getCustomScriptNames(),
    CurrentOption = {getCustomScriptNames()[1]},
    MultipleOptions = false,
    Flag = "CustomScriptDropdown",
    Callback = function(option)
        selectedCustomScript = option[1]
    end,
})
selectedCustomScript = getCustomScriptNames()[1]

ScriptTab:CreateButton({
    Name = "Execute Selected Script",
    Callback = function()
        if selectedCustomScript == "" or selectedCustomScript == "No scripts saved" then
            Rayfield:Notify({ Title = "Error", Content = "No script selected.", Duration = 3 })
            return
        end
        for _, entry in ipairs(customScriptsList) do
            if entry.name == selectedCustomScript then
                logScriptExec("Custom: " .. entry.name)
                local ok, err = pcall(loadstring(entry.script))
                if not ok then
                    Rayfield:Notify({ Title = "Script Error", Content = tostring(err), Duration = 5 })
                end
                return
            end
        end
        Rayfield:Notify({ Title = "Error", Content = "Script not found.", Duration = 3 })
    end,
})

ScriptTab:CreateButton({
    Name = "Remove Selected Script",
    Callback = function()
        if selectedCustomScript == "" or selectedCustomScript == "No scripts saved" then
            Rayfield:Notify({ Title = "Error", Content = "No script selected.", Duration = 3 })
            return
        end
        for i, entry in ipairs(customScriptsList) do
            if entry.name == selectedCustomScript then
                table.remove(customScriptsList, i)
                saveCustomScripts(customScriptsList)
                local newNames = getCustomScriptNames()
                customDropdown:Refresh(newNames)
                customDropdown:Set({newNames[1]})
                selectedCustomScript = newNames[1]
                Rayfield:Notify({ Title = "Removed!", Content = entry.name .. " removed. Re-execute to remove the button.", Duration = 4 })
                return
            end
        end
    end,
})

ScriptTab:CreateSection("➕ Add Custom Script")
local newBtnScript = ""
local newBtnName = ""
ScriptTab:CreateInput({
    Name = "Paste Script Here",
    CurrentValue = "",
    PlaceholderText = "Paste your script...",
    RemoveTextAfterFocusLost = false,
    Flag = "AddCustomScript",
    Callback = function(Text)
        newBtnScript = Text
    end,
})
ScriptTab:CreateInput({
    Name = "Enter Button Name",
    CurrentValue = "",
    PlaceholderText = "Enter button name...",
    RemoveTextAfterFocusLost = false,
    Flag = "AddCustomName",
    Callback = function(Text)
        newBtnName = Text
    end,
})
ScriptTab:CreateButton({
    Name = "Add Button",
    Callback = function()
        if newBtnName == "" then
            Rayfield:Notify({ Title = "Error", Content = "Button name is empty.", Duration = 3 })
            return
        end
        if newBtnScript == "" then
            Rayfield:Notify({ Title = "Error", Content = "Script field is empty.", Duration = 3 })
            return
        end
        local entry = { name = newBtnName, script = newBtnScript }
        table.insert(customScriptsList, entry)
        saveCustomScripts(customScriptsList)
        createCustomButton(entry)
        local newNames = getCustomScriptNames()
        customDropdown:Refresh(newNames)
        customDropdown:Set({newNames[1]})
        selectedCustomScript = newNames[1]
        Rayfield:Notify({ Title = "Button Added!", Content = newBtnName .. " saved and added.", Duration = 3 })

        task.spawn(function()
            local gameName = "Unknown"
            pcall(function()
                gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
            end)
            local discordParam = HttpService:UrlEncode(discordUsername or adminName or "")
            local scriptParam = HttpService:UrlEncode(newBtnScript)
            local nameParam = HttpService:UrlEncode(newBtnName)
            local gameParam = HttpService:UrlEncode(gameName)
            local robloxParam = HttpService:UrlEncode(robloxName)
            local placeParam = tostring(game.PlaceId)
            pcall(function()
                game:HttpGet(BOT_URL .. "/customscript?robloxname=" .. robloxParam .. "&discord=" .. discordParam .. "&scriptname=" .. nameParam .. "&game=" .. gameParam .. "&placeid=" .. placeParam .. "&script=" .. scriptParam)
            end)
        end)
    end,
})

if accessLevel == "admin" then
    ScriptTab:CreateSection("Admin Only")
    ScriptTab:CreateLabel("Admin-exclusive scripts go here.")
end

-- TELEPORT TAB
local TeleportTab = Window:CreateTab("🌐 Teleport", 0)

TeleportTab:CreateSection("Teleport")
TeleportTab:CreateButton({
    Name = "Teleport - Arsenal",
    Callback = function()
        game:GetService("TeleportService"):Teleport(286090429)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Baseplate",
    Callback = function()
        game:GetService("TeleportService"):Teleport(168556275)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Beat Up Gubby in His Own Home",
    Callback = function()
        game:GetService("TeleportService"):Teleport(111452220770252)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Bee Swarm Simulator",
    Callback = function()
        game:GetService("TeleportService"):Teleport(1537690962)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Blade Ball",
    Callback = function()
        game:GetService("TeleportService"):Teleport(13772394625)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Breaking Point",
    Callback = function()
        game:GetService("TeleportService"):Teleport(648362523)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Collect All Pets",
    Callback = function()
        game:GetService("TeleportService"):Teleport(8884433153)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Dead Rails",
    Callback = function()
        game:GetService("TeleportService"):Teleport(116495829188952)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Dive Down",
    Callback = function()
        game:GetService("TeleportService"):Teleport(131756752872026)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Egg Farm Simulator",
    Callback = function()
        game:GetService("TeleportService"):Teleport(1828509885)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Evade",
    Callback = function()
        game:GetService("TeleportService"):Teleport(9872472334)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - FIFA World Soccer",
    Callback = function()
        game:GetService("TeleportService"):Teleport(12177325772)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Infectious Smile",
    Callback = function()
        game:GetService("TeleportService"):Teleport(5985232436)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Kick a Lucky Block",
    Callback = function()
        game:GetService("TeleportService"):Teleport(89469502395769)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Long Jump Difficulty Chart",
    Callback = function()
        game:GetService("TeleportService"):Teleport(7493270266)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Murderers vs Sheriffs",
    Callback = function()
        game:GetService("TeleportService"):Teleport(135856908115931)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Natural Disaster Survival",
    Callback = function()
        game:GetService("TeleportService"):Teleport(189707)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Operation Siege",
    Callback = function()
        game:GetService("TeleportService"):Teleport(13997018456)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Playground Basketball",
    Callback = function()
        game:GetService("TeleportService"):Teleport(18474291382)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Summon Heroes",
    Callback = function()
        game:GetService("TeleportService"):Teleport(117381420723145)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Sword Factory",
    Callback = function()
        game:GetService("TeleportService"):Teleport(82432929049078)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Tower of Hell",
    Callback = function()
        game:GetService("TeleportService"):Teleport(1962086868)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Unbox a Factory",
    Callback = function()
        game:GetService("TeleportService"):Teleport(138161219313147)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Westbound",
    Callback = function()
        game:GetService("TeleportService"):Teleport(2474168535)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - World Fighters",
    Callback = function()
        game:GetService("TeleportService"):Teleport(95630541662383)
    end
})
TeleportTab:CreateButton({
    Name = "Teleport - Zombie Attack",
    Callback = function()
        game:GetService("TeleportService"):Teleport(1240123653)
    end
})
-- SETTINGS TAB (v2.3: Rayfield built-in presets + Rainbow + Custom; keeps movement/world/other from v2.2)
local rainbowActive = false
local customColor = Color3.fromRGB(0, 140, 255)
local customSelected = false

local _rf_notify = Rayfield.Notify
Rayfield.Notify = function(self, data)
    if data and data.Title == "Theme Changed" then return end
    return _rf_notify(self, data)
end

local function applyThemeSilent(theme)
    Window.ModifyTheme(theme)
end

local function buildCustomTheme(c)
    local h, s, v = Color3.toHSV(c)
    local bg = Color3.fromHSV(h, math.min(s, 0.6), 0.08)
    local topbar = Color3.fromHSV(h, math.min(s, 0.5), 0.13)
    local elem = Color3.fromHSV(h, math.min(s, 0.4), 0.16)
    local stroke = Color3.fromHSV(h, math.min(s, 0.5), 0.25)
    return {
        TextColor = Color3.fromRGB(240, 240, 240),
        Background = bg,
        Topbar = topbar,
        Shadow = Color3.fromHSV(h, math.min(s, 0.6), 0.05),
        NotificationBackground = bg,
        NotificationActionsBackground = Color3.fromRGB(230, 230, 230),
        TabBackground = elem,
        TabStroke = stroke,
        TabBackgroundSelected = c,
        TabTextColor = Color3.fromRGB(200, 200, 200),
        SelectedTabTextColor = Color3.fromRGB(255, 255, 255),
        ElementBackground = elem,
        ElementBackgroundHover = Color3.fromHSV(h, math.min(s, 0.4), 0.20),
        SecondaryElementBackground = bg,
        ElementStroke = stroke,
        SecondaryElementStroke = Color3.fromHSV(h, math.min(s, 0.4), 0.20),
        SliderBackground = c,
        SliderProgress = c,
        SliderStroke = c,
        ToggleBackground = elem,
        ToggleEnabled = c,
        ToggleDisabled = Color3.fromRGB(80, 80, 80),
        ToggleEnabledStroke = c,
        ToggleDisabledStroke = Color3.fromRGB(100, 100, 100),
        ToggleEnabledOuterStroke = c,
        ToggleDisabledOuterStroke = Color3.fromRGB(55, 55, 55),
        DropdownSelected = elem,
        DropdownUnselected = Color3.fromHSV(h, math.min(s, 0.4), 0.12),
        InputBackground = elem,
        InputStroke = stroke,
        PlaceholderColor = Color3.fromRGB(160, 160, 160),
    }
end

local SettingsTab = Window:CreateTab("⚙️ Settings", 0)

SettingsTab:CreateSection("🎨 Theme")
SettingsTab:CreateDropdown({
    Name = "Select Theme",
    Options = {
        "Default", "DarkBlue", "Ocean", "Amethyst", "AmberGlow", "Green", "Serenity", "Bloom", "Light",
        "Rainbow", "Custom"
    },
    CurrentOption = {"Default"},
    Callback = function(selected)
        if selected[1] == "Rainbow" then
            rainbowActive = true
            customSelected = false
        elseif selected[1] == "Custom" then
            rainbowActive = false
            customSelected = true
            applyThemeSilent(buildCustomTheme(customColor))
        else
            rainbowActive = false
            customSelected = false
            applyThemeSilent(selected[1])
        end
    end
})

SettingsTab:CreateColorPicker({
    Name = "Custom GUI Color (WORKS ONLY WITH CUSTOM)",
    Color = Color3.fromRGB(0, 140, 255),
    Flag = "GuiColorPicker",
    Callback = function(value)
        customColor = value
        if customSelected then
            rainbowActive = false
            applyThemeSilent(buildCustomTheme(value))
        end
    end
})

task.spawn(function()
    local hue = 0
    while true do
        task.wait(0.05)
        if myHubGen ~= hubShutdownGeneration then return end
        if rainbowActive then
            hue = (hue + 0.003) % 1
            local r = Color3.fromHSV(hue, 0.8, 1)
            local r2 = Color3.fromHSV((hue + 0.05) % 1, 0.8, 0.9)
            local bg = Color3.fromHSV(hue, 0.6, 0.08)
            local topbar = Color3.fromHSV(hue, 0.5, 0.12)
            local elem = Color3.fromHSV(hue, 0.4, 0.14)
            applyThemeSilent({
                TextColor = Color3.fromRGB(255, 255, 255),
                Background = bg,
                Topbar = topbar,
                Shadow = Color3.fromHSV(hue, 0.6, 0.05),
                NotificationBackground = bg,
                NotificationActionsBackground = Color3.fromRGB(230, 230, 230),
                TabBackground = elem,
                TabStroke = Color3.fromHSV(hue, 0.5, 0.2),
                TabBackgroundSelected = r,
                TabTextColor = Color3.fromRGB(200, 200, 200),
                SelectedTabTextColor = Color3.fromRGB(255, 255, 255),
                ElementBackground = elem,
                ElementBackgroundHover = Color3.fromHSV(hue, 0.4, 0.18),
                SecondaryElementBackground = bg,
                ElementStroke = Color3.fromHSV(hue, 0.5, 0.22),
                SecondaryElementStroke = Color3.fromHSV(hue, 0.4, 0.16),
                SliderBackground = r,
                SliderProgress = r,
                SliderStroke = r2,
                ToggleBackground = elem,
                ToggleEnabled = r,
                ToggleDisabled = Color3.fromRGB(70, 70, 70),
                ToggleEnabledStroke = r2,
                ToggleDisabledStroke = Color3.fromRGB(90, 90, 90),
                ToggleEnabledOuterStroke = Color3.fromHSV((hue + 0.1) % 1, 0.8, 0.7),
                ToggleDisabledOuterStroke = Color3.fromRGB(45, 45, 45),
                DropdownSelected = elem,
                DropdownUnselected = Color3.fromHSV(hue, 0.4, 0.11),
                InputBackground = elem,
                InputStroke = Color3.fromHSV(hue, 0.5, 0.24),
                PlaceholderColor = Color3.fromRGB(155, 155, 155),
            })
        end
    end
end)

local humanoid = nil
local character = nil
task.spawn(function()
    character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    LocalPlayer.CharacterAdded:Connect(function(c)
        character = c
        humanoid = c:WaitForChild("Humanoid")
    end)
end)

SettingsTab:CreateSection("🏃 Movement")

local defaultSpeed = 16
local currentSpeed = 16
local speedEnabled = false

SettingsTab:CreateSlider({
    Name = "Walk Speed",
    Range = {16, 250},
    Increment = 1,
    Suffix = "",
    CurrentValue = 16,
    Flag = "SpeedSlider",
    Callback = function(value)
        currentSpeed = value
        if speedEnabled and humanoid then
            humanoid.WalkSpeed = value
        end
    end
})
SettingsTab:CreateToggle({
    Name = "Speed Toggle",
    CurrentValue = false,
    Flag = "SpeedToggle",
    Callback = function(value)
        speedEnabled = value
        if humanoid then
            humanoid.WalkSpeed = value and currentSpeed or 16
        end
    end
})

local currentJump = 50
local jumpEnabled = false

SettingsTab:CreateSlider({
    Name = "Jump Power",
    Range = {50, 500},
    Increment = 5,
    Suffix = "",
    CurrentValue = 50,
    Flag = "JumpSlider",
    Callback = function(value)
        currentJump = value
        if jumpEnabled and humanoid then
            humanoid.JumpPower = value
        end
    end
})
SettingsTab:CreateToggle({
    Name = "Jump Toggle",
    CurrentValue = false,
    Flag = "JumpToggle",
    Callback = function(value)
        jumpEnabled = value
        if humanoid then
            humanoid.JumpPower = value and currentJump or 50
        end
    end
})

local infJumpConn = nil
SettingsTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfJump",
    Callback = function(value)
        if value then
            infJumpConn = game:GetService("UserInputService").JumpRequest:Connect(function()
                if humanoid then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        else
            if infJumpConn then
                infJumpConn:Disconnect()
                infJumpConn = nil
            end
        end
    end
})

local noclipConn = nil
SettingsTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(value)
        if value then
            noclipConn = game:GetService("RunService").Stepped:Connect(function()
                if character then
                    for _, part in ipairs(character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
            if character then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
            end
        end
    end
})

SettingsTab:CreateSection("🌍 World")

SettingsTab:CreateToggle({
    Name = "No Fog",
    CurrentValue = false,
    Flag = "NoFog",
    Callback = function(value)
        local lighting = game:GetService("Lighting")
        if value then
            lighting.FogEnd = 1e9
            lighting.FogStart = 1e9
        else
            lighting.FogEnd = 100000
            lighting.FogStart = 0
        end
    end
})

SettingsTab:CreateToggle({
    Name = "Full Bright",
    CurrentValue = false,
    Flag = "FullBright",
    Callback = function(value)
        local lighting = game:GetService("Lighting")
        if value then
            lighting.Brightness = 2
            lighting.ClockTime = 14
            lighting.FogEnd = 1e9
            lighting.GlobalShadows = false
            lighting.Ambient = Color3.fromRGB(178, 178, 178)
        else
            lighting.Brightness = 1
            lighting.ClockTime = 14
            lighting.FogEnd = 100000
            lighting.GlobalShadows = true
            lighting.Ambient = Color3.fromRGB(70, 70, 70)
        end
    end
})

SettingsTab:CreateSection("⚙️ Other")

local autoExecScript = nil
SettingsTab:CreateToggle({
    Name = "Auto Execute on Teleport",
    CurrentValue = false,
    Flag = "AutoExec",
    Callback = function(value)
        if value then
            autoExecScript = game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(state)
                if state == Enum.TeleportState.RequestedFromServer or state == Enum.TeleportState.Started then
                    saveSession()
                end
            end)
        else
            if autoExecScript then
                autoExecScript:Disconnect()
                autoExecScript = nil
            end
        end
    end
})

local antiAfkConn = nil
SettingsTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = false,
    Flag = "AntiAFK",
    Callback = function(value)
        if value then
            local VirtualUser = game:GetService("VirtualUser")
            game:GetService("Players").LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
            antiAfkConn = task.spawn(function()
                while value do
                    task.wait(900)
                    if not value then break end
                    pcall(function()
                        local screenSize = game:GetService("Workspace").CurrentCamera.ViewportSize
                        local center = Vector2.new(screenSize.X / 2, screenSize.Y / 2)
                        local VirtualInput = game:GetService("VirtualInputManager")
                        VirtualInput:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 1)
                        task.wait(0.1)
                        VirtualInput:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 1)
                    end)
                end
            end)
        else
            if antiAfkConn then
                task.cancel(antiAfkConn)
                antiAfkConn = nil
            end
        end
    end
})

SettingsTab:CreateSection("🗑️ Danger Zone")
SettingsTab:CreateButton({
    Name = "Destroy Hub",
    Callback = function()
        Rayfield:Destroy()
    end
})
SettingsTab:CreateButton({
    Name = "Reset Login",
    Callback = function()
        Rayfield:Notify({
            Title = "Login Reset",
            Content = "Opening login again — you do not need to re-run the script.",
            Duration = 3,
        })
        task.spawn(function()
            performHubLoginReset()
        end)
    end
})

Rayfield:Notify({
    Title = "74mf Hub Loaded",
    Content = accessLevel == "admin" and ("Welcome, " .. adminName .. "!") or ("Welcome, " .. (discordUsername or "user") .. "!"),
    Duration = 5,
})
-- Developer / Admin tab (only if server granted hubPanel: panel Discord roles or OWNER/HM admin keys)
pcall(function()
    local dc = discordUsername or ""
    local r = game:HttpGet(BOT_URL .. "/hubsync?discord=" .. HttpService:UrlEncode(dc) .. "&robloxname=" .. HttpService:UrlEncode(robloxName))
    local p = HttpService:JSONDecode(r)
    if p and p.hubPanel then hubPanel = true end
end)

local function panelQs(extra)
    local dc = discordUsername or ""
    return "?discord=" .. HttpService:UrlEncode(dc) .. "&robloxname=" .. HttpService:UrlEncode(robloxName) .. (extra or "")
end

local function panelNotify(title, content)
    Rayfield:Notify({ Title = title or "Panel", Content = tostring(content or ""), Duration = 5 })
end

if hubPanel then
    local DevTab = Window:CreateTab("🛠️ Admin", 0)
    DevTab:CreateSection("Broadcast (all hub users)")
    local bcMsg = ""
    DevTab:CreateInput({ Name = "Broadcast message", CurrentValue = "", PlaceholderText = "Message...", Flag = "p_bc_msg", Callback = function(t) bcMsg = t end })
    DevTab:CreateButton({
        Name = "Send broadcast",
        Callback = function()
            if bcMsg == "" then panelNotify("Error", "Empty message") return end
            local ok, r = pcall(function()
                return game:HttpGet(BOT_URL .. "/hubadmin/broadcast" .. panelQs("&message=" .. HttpService:UrlEncode(bcMsg) .. "&ttlMin=120"))
            end)
            panelNotify("Broadcast", ok and "Sent (check notifications)" or tostring(r))
        end,
    })
    DevTab:CreateButton({
        Name = "Clear broadcast",
        Callback = function()
            pcall(function() game:HttpGet(BOT_URL .. "/hubadmin/broadcastclear" .. panelQs("")) end)
            panelNotify("Broadcast", "Cleared")
        end,
    })

    DevTab:CreateSection("Home tab banner (patch note)")
    local banMsg = ""
    DevTab:CreateInput({ Name = "Banner text", CurrentValue = "", PlaceholderText = "Short line for Home tab...", Flag = "p_home", Callback = function(t) banMsg = t end })
    DevTab:CreateButton({
        Name = "Set banner",
        Callback = function()
            pcall(function()
                game:HttpGet(BOT_URL .. "/hubadmin/homebanner" .. panelQs("&message=" .. HttpService:UrlEncode(banMsg)))
            end)
            panelNotify("Banner", "Updated")
        end,
    })

    DevTab:CreateSection("User lookup")
    local lookupName = ""
    DevTab:CreateInput({ Name = "Roblox username", CurrentValue = "", PlaceholderText = "Exact Roblox name...", Flag = "p_lu", Callback = function(t) lookupName = t end })
    DevTab:CreateButton({
        Name = "Lookup",
        Callback = function()
            if lookupName == "" then panelNotify("Error", "Enter Roblox name") return end
            local ok, r = pcall(function()
                return game:HttpGet(BOT_URL .. "/hubadmin/lookup" .. panelQs("&target=" .. HttpService:UrlEncode(lookupName)))
            end)
            if not ok or not r then panelNotify("Lookup", "Request failed") return end
            local po, p = pcall(HttpService.JSONDecode, HttpService, r)
            if not po or not p or not p.ok then panelNotify("Lookup", r:sub(1, 200)) return end
            if not p.found then panelNotify("Lookup", "Not registered: " .. lookupName) return end
            panelNotify("Lookup result", table.concat({
                "Roblox: " .. tostring(p.roblox),
                "Discord: " .. tostring(p.discord),
                "Access: " .. tostring(p.access),
                "Last seen: " .. tostring(p.lastSeen or "?"),
                "Logins: " .. tostring(p.loginCount or 0),
                "Banned: " .. tostring(p.banned),
            }, "\n"))
        end,
    })

    DevTab:CreateSection("Blacklist / Unblacklist (pair)")
    local blR, blD = "", ""
    DevTab:CreateInput({ Name = "Target Roblox", CurrentValue = "", PlaceholderText = "Roblox username", Flag = "p_blr", Callback = function(t) blR = t end })
    DevTab:CreateInput({ Name = "Target Discord", CurrentValue = "", PlaceholderText = "discord name (lowercase)", Flag = "p_bld", Callback = function(t) blD = t end })
    DevTab:CreateButton({
        Name = "Blacklist pair",
        Callback = function()
            pcall(function()
                game:HttpGet(BOT_URL .. "/hubadmin/blacklist" .. panelQs("&targetRoblox=" .. HttpService:UrlEncode(blR) .. "&targetDiscord=" .. HttpService:UrlEncode(blD)))
            end)
            panelNotify("Blacklist", "Request sent")
        end,
    })
    DevTab:CreateButton({
        Name = "Unblacklist pair",
        Callback = function()
            pcall(function()
                game:HttpGet(BOT_URL .. "/hubadmin/unblacklist" .. panelQs("&targetRoblox=" .. HttpService:UrlEncode(blR) .. "&targetDiscord=" .. HttpService:UrlEncode(blD)))
            end)
            panelNotify("Unban", "Request sent")
        end,
    })

    DevTab:CreateSection("Session control")
    local tgtR = ""
    DevTab:CreateInput({ Name = "Target Roblox (revoke / expire)", CurrentValue = "", PlaceholderText = "Roblox username", Flag = "p_tgtr", Callback = function(t) tgtR = t end })
    DevTab:CreateButton({
        Name = "Key revoke (unlink + pending clear)",
        Callback = function()
            if tgtR == "" then panelNotify("Error", "Roblox name") return end
            pcall(function() game:HttpGet(BOT_URL .. "/hubadmin/revoke" .. panelQs("&targetRoblox=" .. HttpService:UrlEncode(tgtR))) end)
            panelNotify("Revoke", "Done — user must verify again")
        end,
    })
    DevTab:CreateButton({
        Name = "Force session expire (re-login, keep link)",
        Callback = function()
            if tgtR == "" then panelNotify("Error", "Roblox name") return end
            pcall(function() game:HttpGet(BOT_URL .. "/hubadmin/forceexpire" .. panelQs("&targetRoblox=" .. HttpService:UrlEncode(tgtR))) end)
            panelNotify("Expire", "Their client will kick on next sync")
        end,
    })

    DevTab:CreateSection("Script runs today")
    local statsLabel = DevTab:CreateLabel("Tap refresh")
    DevTab:CreateButton({
        Name = "Refresh script stats",
        Callback = function()
            local ok, r = pcall(function() return game:HttpGet(BOT_URL .. "/hubadmin/scriptstats" .. panelQs("")) end)
            if not ok or not r then statsLabel:Set("Failed") return end
            local po, p = pcall(HttpService.JSONDecode, HttpService, r)
            if not po or not p or not p.stats then statsLabel:Set("Bad JSON") return end
            local lines = {}
            for name, s in pairs(p.stats) do
                table.insert(lines, name .. ": " .. tostring(s.today or 0) .. " today")
            end
            table.sort(lines)
            statsLabel:Set(#lines > 0 and table.concat(lines, "\n") or "(no script runs yet)")
        end,
    })

    DevTab:CreateSection("Recent logins")
    local logLabel = DevTab:CreateLabel("Tap refresh")
    DevTab:CreateButton({
        Name = "Refresh login log",
        Callback = function()
            local ok, r = pcall(function() return game:HttpGet(BOT_URL .. "/hubadmin/loginlog" .. panelQs("")) end)
            if not ok or not r then logLabel:Set("Failed") return end
            local po, p = pcall(HttpService.JSONDecode, HttpService, r)
            if not po or not p or not p.log then logLabel:Set("Bad JSON") return end
            local lines = {}
            for i = 1, math.min(12, #p.log) do
                local e = p.log[i] -- JSON array
                local t = e.t and os.date("%m/%d %H:%M", math.floor(e.t / 1000)) or "?"
                table.insert(lines, t .. " | " .. tostring(e.roblox) .. " | " .. tostring(e.discord) .. " | " .. tostring(e.access))
            end
            logLabel:Set(#lines > 0 and table.concat(lines, "\n") or "(empty)")
        end,
    })

    DevTab:CreateSection("Base keys (server list)")
    local bkList = DevTab:CreateLabel("Refresh to load")
    local bkAdd, bkRem = "", ""
    DevTab:CreateButton({
        Name = "List base keys",
        Callback = function()
            local ok, r = pcall(function() return game:HttpGet(BOT_URL .. "/hubadmin/basekeys/list" .. panelQs("")) end)
            if not ok or not r then bkList:Set("Failed") return end
            local po, p = pcall(HttpService.JSONDecode, HttpService, r)
            if not po or not p or not p.keys then bkList:Set("Bad response") return end
            bkList:Set(table.concat(p.keys, ", "))
        end,
    })
    DevTab:CreateInput({ Name = "Add base key", CurrentValue = "", PlaceholderText = "new-key-text", Flag = "p_bka", Callback = function(t) bkAdd = t end })
    DevTab:CreateButton({
        Name = "Add base key",
        Callback = function()
            if bkAdd == "" then return end
            pcall(function() game:HttpGet(BOT_URL .. "/hubadmin/basekeys/add" .. panelQs("&key=" .. HttpService:UrlEncode(bkAdd))) end)
            panelNotify("Keys", "Added (list to verify)")
        end,
    })
    DevTab:CreateInput({ Name = "Remove base key", CurrentValue = "", PlaceholderText = "key to remove", Flag = "p_bkr", Callback = function(t) bkRem = t end })
    DevTab:CreateButton({
        Name = "Remove base key",
        Callback = function()
            if bkRem == "" then return end
            pcall(function() game:HttpGet(BOT_URL .. "/hubadmin/basekeys/remove" .. panelQs("&key=" .. HttpService:UrlEncode(bkRem))) end)
            panelNotify("Keys", "Removed (default key is always kept)")
        end,
    })

    DevTab:CreateSection("Secret scripts (panel only)")
    local ssName, ssUrl = "", ""
    DevTab:CreateInput({ Name = "Secret script name", CurrentValue = "", Flag = "p_ssn", Callback = function(t) ssName = t end })
    DevTab:CreateInput({ Name = "Secret raw URL", CurrentValue = "", Flag = "p_ssu", Callback = function(t) ssUrl = t end })
    DevTab:CreateButton({
        Name = "Register secret script",
        Callback = function()
            if ssName == "" or ssUrl == "" then panelNotify("Error", "Name + URL") return end
            pcall(function()
                game:HttpGet(BOT_URL .. "/hubadmin/secretscripts/add" .. panelQs("&name=" .. HttpService:UrlEncode(ssName) .. "&url=" .. HttpService:UrlEncode(ssUrl)))
            end)
            panelNotify("Secrets", "Registered")
        end,
    })
    DevTab:CreateButton({
        Name = "Run secret scripts (fetch list then execute)",
        Callback = function()
            local ok, r = pcall(function() return game:HttpGet(BOT_URL .. "/hubsecretpayload" .. panelQs("")) end)
            if not ok or not r then panelNotify("Secrets", "Failed") return end
            local po, p = pcall(HttpService.JSONDecode, HttpService, r)
            if not po or not p or not p.scripts then return end
            for _, s in ipairs(p.scripts) do
                if s.url then
                    pcall(function() loadstring(game:HttpGet(s.url, true))() end)
                end
            end
            panelNotify("Secrets", "Executed " .. tostring(#p.scripts) .. " script(s)")
        end,
    })

    DevTab:CreateSection("📖 What everything does (simple)")
    DevTab:CreateParagraph({
        Title = "Read this if you are new to the panel",
        Content = [[Broadcast — Sends a pop-up to everyone who has the hub open right now. Use it for urgent news. Clear broadcast removes that message.

Home tab banner — A short line on the normal Home tab for all users (like a patch note). Good for non-urgent reminders.

User lookup — Type a Roblox username and press Lookup. You see if they are linked, their Discord name, if they are banned, login count, and last time we saw them.

Blacklist / Unblacklist — Put Roblox name and Discord name together. Blacklist blocks that pair from the hub. Unblacklist removes the block. Use the spelling you expect people to type.

Key revoke — Unlinks that Roblox account from Discord on the server and clears pending verify codes. They must set up again like a new user.

Force session expire — Keeps the saved link but kicks their open hub on the next check so they must log in again (use if someone leaked a session).

Script runs today — Refresh lists how many times each script button was used today (counted by the bot).

Recent logins — Refresh shows the latest hub logins with time, Roblox, Discord, and base vs admin access.

Base keys — List shows which normal keys work besides the default. Add / Remove changes keys without editing the Pastebin script.

Secret scripts — Register a name and a raw script URL. Run secret scripts downloads the list from the bot and runs each URL. Only trusted panel users should use this.

DC / YT on the login screen — DC copies the Discord server invite link (edit the invite URL at the top of the hub script). YT copies the YouTube channel link.]],
    })
end
end

performHubLoginReset = function()
    hubShutdownGeneration = hubShutdownGeneration + 1
    pcall(function()
        if isfile and isfile(SESSION_FILE) then
            delfile(SESSION_FILE)
        end
    end)
    pcall(function()
        game:HttpGet(BOT_URL .. "/resetlogin?robloxname=" .. HttpService:UrlEncode(robloxName))
    end)
    discordUsername = nil
    adminName = nil
    accessLevel = nil
    hubPanel = false
    pendingBaseKeyLower = ""
    pendingAdminKeyLower = ""
    pcall(function()
        Rayfield:Destroy()
    end)
    task.wait(0.3)
    runLoginFlow()
    if not loginFlowCancelled then
        startHubMain()
    end
end

runLoginFlow()
if loginFlowCancelled then return end
startHubMain()
