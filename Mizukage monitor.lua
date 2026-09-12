--[[ ═══════════════════════════════════════════════════════════
     ✧ Mizukage Monitor v7.0 — Total Upgrade ✧
     ✧ Skip Internal • Tabs GUI • Live Monitor • Settings ✧
═══════════════════════════════════════════════════════════ ]]--

local WEBHOOK_URL = "https://discord.com/api/webhooks/1527913356185571430/_n_0VAkN4pt0tKvtI5mejTyYYLb7pw1aawFf1cuLGYBTvwVDS-FqLOlJ4Her15oUIH90"

if getgenv().MizuMonitorActive then
    warn("[Mizukage] Monitor sudah berjalan.")
    return
end

local function safeGetService(name)
    local ok, svc = pcall(game.GetService, game, name)
    return ok and svc or nil
end

local CoreGui      = safeGetService("CoreGui")
local Players      = safeGetService("Players")
local RunService   = safeGetService("RunService")
local TweenService = safeGetService("TweenService")
local UIS          = safeGetService("UserInputService")
local HttpService  = safeGetService("HttpService")

if not Players or not RunService or not TweenService or not UIS then
    warn("[Mizukage] FATAL: Service tidak tersedia.")
    return
end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

getgenv().MizuMonitorActive = true

local decompileFn = decompile or (syn and syn.decompile) or nil

-- ═══════════════════════════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════════════════════════
local CONFIG = {
    VERSION           = "7.0",
    MAX_LOGS          = 100,
    -- LOGO
    LOGO_IMAGE = "rbxassetid://104266190557772",
    LOGO_FALLBACK_TEXT = "M",
    -- SCAN
    SCAN_DELAY           = 0.08,
    SCAN_MAX_PER_SVC     = 200,
    SCAN_MIN_SRC_LEN     = 20,
    SCAN_MAX_SRC_CHUNK   = 2000 * 1024,
    SCAN_FLUSH_EVERY     = 15,
    SCAN_GC_EVERY        = 10,
    SCAN_HARD_GC_EVERY   = 30,
    SCAN_MEM_WARN_MB     = 180,
    SCAN_MEM_FLUSH_MB    = 220,
    SCAN_PARTIAL_EVERY   = 25,
    SCAN_WATCHDOG_S      = 15,
    -- DEEP
    DEEP_SCAN_ENABLED    = true,
    DEEP_SCAN_MAX_TARGET = 10,
    -- ⭐ SKIP INTERNAL (fix crash)
    SKIP_NAMES = {
        "RbxCharacterSounds",
        "RbxCharacterSoundsLocal",
        "RbxCharacterSoundsServer",
        "Animate",
        "Health",
        "Sound",
        "CameraScript",
        "ControlScript",
        "PlayerModule",
        "ChatScript",
        "BubbleChat",
        "ChatMain",
        "ChatServiceRunner",
        "DefaultChatSystemChatEvents",
        "PlayerScriptsLoader",
        "SoundController",
        "FaceAnimator",
        "TouchTransmitter",
        "DummyAnimator",
        "PlaybackController",
        "Freecam",
    },
    SKIP_PATHS = {
        "StarterCharacterScripts",
        "StarterPlayerScripts",
        "PlayerScripts",
        "Humanoid",
        "SoundService",
        "ChatModules",
        "Chat.",
    },
    -- SERVICES
    ALL_SERVICES = {
        "ReplicatedStorage", "ReplicatedFirst",
        "StarterPlayer", "StarterGui", "StarterPack",
        "ServerScriptService", "ServerStorage",
    },
    -- THEME
    THEME = {
        BgBase    = Color3.fromRGB(10, 10, 15),
        CardBg    = Color3.fromRGB(18, 18, 26),
        CardHover = Color3.fromRGB(26, 26, 38),
        Accent    = Color3.fromRGB(0, 225, 255),
        TextWhite = Color3.fromRGB(240, 240, 245),
        TextMuted = Color3.fromRGB(140, 140, 160),
        Out       = Color3.fromRGB(10, 255, 130),
        Inbound   = Color3.fromRGB(255, 40, 80),
        Scan      = Color3.fromRGB(180, 80, 255),
        Module    = Color3.fromRGB(255, 215, 0),
        Clear     = Color3.fromRGB(255, 140, 0),
        Export    = Color3.fromRGB(50, 150, 255),
        Success   = Color3.fromRGB(80, 220, 120),
        Warning   = Color3.fromRGB(255, 80, 80),
        Live      = Color3.fromRGB(255, 100, 200),
        Gold      = Color3.fromRGB(255, 200, 50),
    },
    HardIgnoreOut = { "mouse", "camera" },
    HardIgnoreIn  = {},
}

-- Runtime settings (bisa diubah via Settings tab)
local Settings = {
    SelectedServices = {},
    ScanDelay = CONFIG.SCAN_DELAY,
    DeepScanEnabled = CONFIG.DEEP_SCAN_ENABLED,
    SkipInternal = true,
}
-- Default: semua service dipilih
for _, s in ipairs(CONFIG.ALL_SERVICES) do
    Settings.SelectedServices[s] = true
end

local State = {
    RecOut        = false,
    RecIn         = false,
    RawBuffer     = {},
    Logs          = {},
    LogQueue      = {},
    TotalCalls    = 0,
    Connections   = {},
    HookedRemotes = {},
    LastDump      = {},
    ScanRunning   = false,
    ScanAbort     = false,
    Filter = { search = "", showOut = true, showIn = true, showScan = true },
    isIgnoredOut = function(name)
        local lower = tostring(name):lower()
        for _, pat in ipairs(CONFIG.HardIgnoreOut) do
            if lower:match(pat) then return true end
        end
        return false
    end,
    isIgnoredIn = function(name) return false end
}

local httpRequest = (syn and syn.request) or (http and http.request) or http_request
    or (fluxus and fluxus.request) or (krnl and krnl.request) or request

local function getPreciseTime()
    return os.date("%H:%M:%S") .. string.format(".%03d", math.floor((os.clock() % 1) * 1000))
end

local function getGameName()
    local Market = safeGetService("MarketplaceService")
    if not Market then return "UnknownGame" end
    local name = "UnknownGame"
    pcall(function()
        local info = Market:GetProductInfo(game.PlaceId)
        name = (info.Name or "UnknownGame"):gsub("[^%w%s]", ""):gsub("%s+", "_")
    end)
    return name
end
local GameName = getGameName()

local function safeFileName(str)
    if not str then return "Unknown" end
    return tostring(str):gsub("[^%w_%-%.]", "_"):gsub("_+", "_"):sub(1, 50)
end

local function getInstancePath(inst)
    if typeof(inst) ~= "Instance" then return "nil" end
    if inst == game then return "game" end
    local parts = {}
    local current = inst
    local depth = 0
    while current and current ~= game and depth < 24 do
        depth = depth + 1
        local name = current.Name
        if name:match("^[%a_][%w_]*$") then
            table.insert(parts, 1, "." .. name)
        else
            table.insert(parts, 1, '["' .. name:gsub('"', '\\"') .. '"]')
        end
        current = current.Parent
    end
    return "game" .. table.concat(parts)
end

local function formatArgs(args, depth, seen)
    depth = depth or 1; seen = seen or {}
    if depth > 3 then return '...' end
    local t = type(args)
    if t == "string" then
        local s = #args > 80 and args:sub(1, 80) .. "..." or args
        return '<font color="#A8E6CF">"' .. s:gsub("<", "&lt;"):gsub(">", "&gt;") .. '"</font>'
    end
    if t == "number"  then return '<font color="#FFD3B6">' .. tostring(args) .. "</font>" end
    if t == "boolean" then return '<font color="#FFAAA5">' .. tostring(args) .. "</font>" end
    if t == "function" then return '<font color="#8888CC">[fn]</font>' end
    if typeof(args) == "Instance" then return '<font color="#FF8B94">' .. args.Name .. "</font>" end
    if t == "table" then
        if seen[args] then return '[CYC]' end
        seen[args] = true
        local parts, count = {}, 0
        local ok = pcall(function()
            for k, v in pairs(args) do
                count = count + 1
                if count > 6 then table.insert(parts, "...") break end
                table.insert(parts, tostring(k) .. "=" .. formatArgs(v, depth + 1, seen))
            end
        end)
        if not ok then return '[table*]' end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "[" .. t .. "]"
end

local function formatArgsPlain(args, depth, seen)
    depth = depth or 1; seen = seen or {}
    if depth > 3 then return "..." end
    local t = type(args)
    if t == "string" then
        local s = #args > 300 and args:sub(1, 300) .. "..." or args
        return string.format("%q", s)
    end
    if t == "number" or t == "boolean" then return tostring(args) end
    if t == "function" then return "function() end" end
    if typeof(args) == "Instance" then return "nil -- " .. args.Name end
    if t == "table" then
        if seen[args] then return "nil -- CYC" end
        seen[args] = true
        local parts, count = {}, 0
        local ok = pcall(function()
            for k, v in pairs(args) do
                count = count + 1
                if count > 10 then table.insert(parts, "...") break end
                local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. tostring(k) .. "]")
                table.insert(parts, key .. " = " .. formatArgsPlain(v, depth + 1, seen))
            end
        end)
        if not ok then return "{}" end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "nil -- " .. t
end

local function getScriptType(obj)
    if obj:IsA("LocalScript") then return "LocalScript"
    elseif obj:IsA("ModuleScript") then return "ModuleScript"
    elseif obj:IsA("Script") then return "ServerScript"
    else return "UnknownScript" end
end

local function getRobloxAvatar(userId)
    local url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="
        .. tostring(userId) .. "&size=420x420&format=Png&isCircular=false"
    local ok, res = pcall(function()
        return httpRequest({ Url = url, Method = "GET" })
    end)
    if ok and res and res.Success and res.Body then
        local decOk, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
        if decOk and data and data.data and data.data[1] then
            return data.data[1].imageUrl
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════
-- BUILD SCREEN
-- ═══════════════════════════════════════════════════════════
print("[Mizukage] Building GUI v" .. CONFIG.VERSION .. "...")

local Screen = Instance.new("ScreenGui")
Screen.Name = "MizuMonitor_" .. tostring(math.random(100000, 999999))
Screen.ResetOnSpawn = false
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() Screen.DisplayOrder = 999 end)
pcall(function() Screen.IgnoreGuiInset = true end)

local attached = false
if CoreGui then
    local ok = pcall(function() Screen.Parent = CoreGui end)
    if ok and Screen.Parent == CoreGui then attached = true end
end
if not attached then
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then
        for _ = 1, 20 do
            task.wait(0.1)
            pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then break end
        end
    end
    if pg then Screen.Parent = pg; attached = true end
end
if not attached then
    warn("[Mizukage] FATAL: Tidak bisa attach GUI.")
    getgenv().MizuMonitorActive = false
    return
end

-- ═══ NOTIF ═══
local MAX_NOTIF = 4
local NotifHolder = Instance.new("Frame", Screen)
NotifHolder.Size = UDim2.new(0, 240, 0, 300)
NotifHolder.Position = UDim2.new(1, -250, 1, -310)
NotifHolder.BackgroundTransparency = 1
NotifHolder.ZIndex = 100
local NLayout = Instance.new("UIListLayout", NotifHolder)
NLayout.SortOrder = Enum.SortOrder.LayoutOrder
NLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NLayout.Padding = UDim.new(0, 4)

local activeNotifs = 0

getgenv().MizuNotify = function(title, text, color, dur)
    if activeNotifs >= MAX_NOTIF then return end
    activeNotifs = activeNotifs + 1
    task.spawn(function()
        pcall(function()
            local frame = Instance.new("Frame", NotifHolder)
            frame.Size = UDim2.new(1, 60, 0, 42)
            frame.BackgroundTransparency = .1
            frame.BackgroundColor3 = CONFIG.THEME.CardBg
            frame.ZIndex = 101
            Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
            local stroke = Instance.new("UIStroke", frame)
            stroke.Color = color; stroke.Thickness = 1; stroke.Transparency = 0.4

            local titleLbl = Instance.new("TextLabel", frame)
            titleLbl.Size = UDim2.new(1, -16, 0, 15)
            titleLbl.Position = UDim2.new(0, 8, 0, 3)
            titleLbl.BackgroundTransparency = 1
            titleLbl.Text = title
            titleLbl.TextColor3 = color
            titleLbl.Font = Enum.Font.GothamBold
            titleLbl.TextSize = 11
            titleLbl.TextXAlignment = Enum.TextXAlignment.Left
            titleLbl.ZIndex = 102

            local bodyLbl = Instance.new("TextLabel", frame)
            bodyLbl.Size = UDim2.new(1, -16, 0, 22)
            bodyLbl.Position = UDim2.new(0, 8, 0, 17)
            bodyLbl.BackgroundTransparency = 1
            bodyLbl.Text = text
            bodyLbl.TextColor3 = CONFIG.THEME.TextWhite
            bodyLbl.Font = Enum.Font.GothamMedium
            bodyLbl.TextSize = 10
            bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
            bodyLbl.TextWrapped = true
            bodyLbl.ZIndex = 102

            TweenService:Create(frame, TweenInfo.new(.3, Enum.EasingStyle.Exponential), {
                Size = UDim2.new(1, 0, 0, 42)
            }):Play()
            task.wait(dur or 3)
            local fade = TweenService:Create(frame, TweenInfo.new(.3, Enum.EasingStyle.Exponential), {
                Size = UDim2.new(1, 80, 0, 42), BackgroundTransparency = 1
            })
            fade:Play()
            TweenService:Create(titleLbl, TweenInfo.new(.25), {TextTransparency = 1}):Play()
            TweenService:Create(bodyLbl,  TweenInfo.new(.25), {TextTransparency = 1}):Play()
            TweenService:Create(stroke,   TweenInfo.new(.25), {Transparency = 1}):Play()
            fade.Completed:Wait()
            frame:Destroy()
        end)
        activeNotifs = activeNotifs - 1
    end)
end

-- ═══ DRAG HELPER ═══
local function makeDraggable(frame, dragHandle)
    local dragging, dragStart, startPos, activeInput = false, nil, nil, nil
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos, activeInput = true, input.Position, frame.Position, input
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if activeInput and input ~= activeInput then return end
        local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
        local isTouchMove = input.UserInputType == Enum.UserInputType.Touch
        if not (isMouseMove or isTouchMove) then return end
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)
    UIS.InputEnded:Connect(function(input)
        if not dragging then return end
        if activeInput and input ~= activeInput then return end
        dragging, activeInput = nil, nil
    end)
end

-- ═══════════════════════════════════════════════════════════
-- MAIN WINDOW — TABBED
-- ═══════════════════════════════════════════════════════════
local Main = Instance.new("Frame", Screen)
Main.Size = UDim2.new(0, 460, 0, 400)
Main.Position = UDim2.new(0.5, -230, 0.5, -200)
Main.BackgroundColor3 = CONFIG.THEME.BgBase
Main.BackgroundTransparency = .08
Main.ClipsDescendants = true
Main.Active = true
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke", Main)
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.new(1, 1, 1)
local grad = Instance.new("UIGradient", MainStroke)
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, CONFIG.THEME.Accent),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50, 50, 70)),
    ColorSequenceKeypoint.new(1, CONFIG.THEME.Scan),
})
grad.Rotation = 45

-- Header
local Header = Instance.new("Frame", Main)
Header.Size = UDim2.new(1, 0, 0, 34)
Header.BackgroundTransparency = 1
Header.Active = true

local HeaderLine = Instance.new("Frame", Header)
HeaderLine.Size = UDim2.new(1, 0, 0, 1)
HeaderLine.Position = UDim2.new(0, 0, 1, 0)
HeaderLine.BackgroundColor3 = CONFIG.THEME.Accent
HeaderLine.BackgroundTransparency = 0.5

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "MIZUKAGE v" .. CONFIG.VERSION
Title.TextColor3 = CONFIG.THEME.TextWhite
Title.Font = Enum.Font.GothamBlack
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left

task.spawn(function()
    while Screen.Parent do
        pcall(function()
            local hue = (tick() * 0.05) % 1
            Title.TextColor3 = Color3.fromHSV(hue, 0.6, 1)
        end)
        task.wait(0.15)
    end
end)

local function makeHeaderBtn(text, pos, hoverColor)
    local btn = Instance.new("TextButton", Header)
    btn.Size = UDim2.new(0, 24, 0, 24)
    btn.Position = pos
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.TextColor3 = CONFIG.THEME.TextMuted
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.AutoButtonColor = false
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(.3), {TextColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(.3), {TextColor3 = CONFIG.THEME.TextMuted}):Play()
    end)
    return btn
end

local BtnMin   = makeHeaderBtn("—", UDim2.new(1, -55, 0, 5), CONFIG.THEME.TextWhite)
local BtnClose = makeHeaderBtn("✕", UDim2.new(1, -28, 0, 5), Color3.fromRGB(255, 60, 60))
makeDraggable(Main, Header)

-- Tab bar
local TabBar = Instance.new("Frame", Main)
TabBar.Size = UDim2.new(1, -16, 0, 28)
TabBar.Position = UDim2.new(0, 8, 0, 40)
TabBar.BackgroundTransparency = 1
local TBL = Instance.new("UIListLayout", TabBar)
TBL.FillDirection = Enum.FillDirection.Horizontal
TBL.Padding = UDim.new(0, 4)

local TabContent = Instance.new("Frame", Main)
TabContent.Size = UDim2.new(1, -16, 1, -110)
TabContent.Position = UDim2.new(0, 8, 0, 74)
TabContent.BackgroundTransparency = 1

local Pages = {}
local TabButtons = {}

local function MakeTab(name, isDefault)
    local b = Instance.new("TextButton", TabBar)
    b.Size = UDim2.new(0, 105, 1, 0)
    b.Text = name
    b.BackgroundColor3 = isDefault and CONFIG.THEME.Accent or CONFIG.THEME.CardBg
    b.TextColor3 = CONFIG.THEME.TextWhite
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = Color3.fromRGB(40, 40, 55)

    local p = Instance.new("ScrollingFrame", TabContent)
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.Visible = isDefault
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = CONFIG.THEME.Accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    local pl = Instance.new("UIListLayout", p)
    pl.Padding = UDim.new(0, 6)
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        p.CanvasSize = UDim2.new(0, 0, 0, pl.AbsoluteContentSize.Y + 8)
    end)

    b.MouseButton1Click:Connect(function()
        for _, pg in pairs(Pages) do pg.Visible = false end
        p.Visible = true
        for _, tb in ipairs(TabBar:GetChildren()) do
            if tb:IsA("TextButton") then
                tb.BackgroundColor3 = CONFIG.THEME.CardBg
            end
        end
        b.BackgroundColor3 = CONFIG.THEME.Accent
    end)

    Pages[name] = p
    TabButtons[name] = b
    return p
end

local ScanPage   = MakeTab("⚡ SCAN", true)
local RemotePage = MakeTab("📡 REMOTE", false)
local ExpPage    = MakeTab("📤 EXPORT", false)
local SetPage    = MakeTab("⚙️ SETTINGS", false)

-- Bottom buttons
local BottomPanel = Instance.new("Frame", Main)
BottomPanel.Size = UDim2.new(1, -16, 0, 30)
BottomPanel.Position = UDim2.new(0, 8, 1, -38)
BottomPanel.BackgroundTransparency = 1
local BLayout = Instance.new("UIListLayout", BottomPanel)
BLayout.FillDirection = Enum.FillDirection.Horizontal
BLayout.Padding = UDim.new(0, 5)

local function makeBottomBtn(text, accentColor, widthScale)
    local btn = Instance.new("TextButton", BottomPanel)
    btn.Size = UDim2.new(widthScale or .16, -4, 1, 0)
    btn.BackgroundColor3 = CONFIG.THEME.CardBg
    btn.Text = text
    btn.TextColor3 = CONFIG.THEME.TextWhite
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(40, 40, 55)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(.3), {BackgroundColor3 = CONFIG.THEME.CardHover}):Play()
        TweenService:Create(stroke, TweenInfo.new(.3), {Color = accentColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(.3), {BackgroundColor3 = CONFIG.THEME.CardBg}):Play()
        TweenService:Create(stroke, TweenInfo.new(.3), {Color = Color3.fromRGB(40, 40, 55)}):Play()
    end)
    return btn
end

local BtnOut    = makeBottomBtn("OUT",    CONFIG.THEME.Out, .15)
local BtnIn     = makeBottomBtn("IN",     CONFIG.THEME.Inbound, .15)
local BtnScan   = makeBottomBtn("SCAN",   CONFIG.THEME.Scan, .18)
local BtnStop   = makeBottomBtn("STOP",   CONFIG.THEME.Warning, .15)
local BtnClear  = makeBottomBtn("CLR",    CONFIG.THEME.Clear, .15)
local BtnExport = makeBottomBtn("EXP",    CONFIG.THEME.Export, .18)

-- ═══════════════════════════════════════════════════════════
-- SCAN TAB — Service Picker + Live Monitor
-- ═══════════════════════════════════════════════════════════
local InfoLbl = Instance.new("TextLabel", ScanPage)
InfoLbl.Size = UDim2.new(1, 0, 0, 34)
InfoLbl.BackgroundColor3 = CONFIG.THEME.CardBg
InfoLbl.BackgroundTransparency = .3
InfoLbl.Text = "  Pilih service, klik SCAN. Internal scripts (RbxCharacterSounds dll) akan di-skip otomatis."
InfoLbl.TextColor3 = CONFIG.THEME.TextMuted
InfoLbl.Font = Enum.Font.GothamMedium
InfoLbl.TextSize = 10
InfoLbl.TextWrapped = true
InfoLbl.TextXAlignment = Enum.TextXAlignment.Left
InfoLbl.TextYAlignment = Enum.TextYAlignment.Center
Instance.new("UICorner", InfoLbl).CornerRadius = UDim.new(0, 5)

-- Live monitor panel (embedded)
local LiveMon = Instance.new("Frame", ScanPage)
LiveMon.Size = UDim2.new(1, 0, 0, 145)
LiveMon.BackgroundColor3 = Color3.fromRGB(5, 5, 10)
LiveMon.BackgroundTransparency = 0.05
LiveMon.BorderSizePixel = 0
Instance.new("UICorner", LiveMon).CornerRadius = UDim.new(0, 8)
local LMStroke = Instance.new("UIStroke", LiveMon)
LMStroke.Color = CONFIG.THEME.Live
LMStroke.Thickness = 1.5

local LMHeader = Instance.new("TextLabel", LiveMon)
LMHeader.Size = UDim2.new(1, -16, 0, 18)
LMHeader.Position = UDim2.new(0, 8, 0, 4)
LMHeader.BackgroundTransparency = 1
LMHeader.Text = "🔴 LIVE SCAN MONITOR"
LMHeader.TextColor3 = CONFIG.THEME.Live
LMHeader.Font = Enum.Font.GothamBlack
LMHeader.TextSize = 10
LMHeader.TextXAlignment = Enum.TextXAlignment.Left

local function makeLiveRow(yPos, color)
    local lbl = Instance.new("TextLabel", LiveMon)
    lbl.Size = UDim2.new(1, -16, 0, 15)
    lbl.Position = UDim2.new(0, 8, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = "-"
    lbl.TextColor3 = color
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.RichText = true
    return lbl
end

local LiveServiceLbl  = makeLiveRow(24, CONFIG.THEME.Accent)
local LiveIndexLbl    = makeLiveRow(39, CONFIG.THEME.TextMuted)
local LiveNameLbl     = makeLiveRow(54, CONFIG.THEME.TextWhite)
local LiveStatLbl     = makeLiveRow(69, CONFIG.THEME.Scan)
local LiveMemLbl      = makeLiveRow(84, CONFIG.THEME.Success)
local LiveLastLbl     = makeLiveRow(99, CONFIG.THEME.Live)

local LiveBarBg = Instance.new("Frame", LiveMon)
LiveBarBg.Size = UDim2.new(1, -16, 0, 8)
LiveBarBg.Position = UDim2.new(0, 8, 1, -22)
LiveBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
LiveBarBg.BorderSizePixel = 0
Instance.new("UICorner", LiveBarBg).CornerRadius = UDim.new(0, 4)

local LiveBarFill = Instance.new("Frame", LiveBarBg)
LiveBarFill.Size = UDim2.new(0, 0, 1, 0)
LiveBarFill.BackgroundColor3 = CONFIG.THEME.Live
LiveBarFill.BorderSizePixel = 0
Instance.new("UICorner", LiveBarFill).CornerRadius = UDim.new(0, 4)

local LiveWatchdogLbl = Instance.new("TextLabel", LiveMon)
LiveWatchdogLbl.Size = UDim2.new(1, -16, 0, 14)
LiveWatchdogLbl.Position = UDim2.new(0, 8, 1, -36)
LiveWatchdogLbl.BackgroundTransparency = 1
LiveWatchdogLbl.Text = ""
LiveWatchdogLbl.TextColor3 = CONFIG.THEME.Warning
LiveWatchdogLbl.Font = Enum.Font.GothamBold
LiveWatchdogLbl.TextSize = 9

local LiveState = {
    Service = "-", Index = 0, Total = 0, Name = "-", Size = 0,
    StartTime = 0, LastProgress = 0, LastScripts = {},
    Success = 0, Fail = 0, Skipped = 0, Internal = 0, Big = 0,
}

local function pushLastScript(name)
    table.insert(LiveState.LastScripts, name)
    if #LiveState.LastScripts > 10 then
        table.remove(LiveState.LastScripts, 1)
    end
end

local function updateLiveDisplay()
    local memMB = math.floor(collectgarbage("count") / 1024)
    local elapsed = LiveState.StartTime > 0 and (os.clock() - LiveState.StartTime) or 0
    local idle = LiveState.LastProgress > 0 and (os.clock() - LiveState.LastProgress) or 0

    LiveServiceLbl.Text = string.format("Service : <b>%s</b>", LiveState.Service)
    LiveIndexLbl.Text = string.format("Index   : %d / %d  |  Elapsed: %.1fs  |  Idle: %.1fs",
        LiveState.Index, LiveState.Total, elapsed, idle)
    LiveNameLbl.Text = string.format("Current : <b>%s</b>%s",
        LiveState.Name,
        LiveState.Size > 0 and ("  [<font color='#FFD700'>" .. math.floor(LiveState.Size / 1024) .. " KB</font>]") or "")
    LiveStatLbl.Text = string.format("Stats   : <b>%d✓</b> / <b>%d✗</b> / <font color='#FFD700'>%d internal</font> / %d big",
        LiveState.Success, LiveState.Fail, LiveState.Internal, LiveState.Big)
    LiveMemLbl.Text = string.format("Memory  : %d MB %s", memMB,
        memMB > CONFIG.SCAN_MEM_WARN_MB and "⚠" or "")

    local lastStr = "-"
    if #LiveState.LastScripts > 0 then
        local parts = {}
        for i = math.max(1, #LiveState.LastScripts - 4), #LiveState.LastScripts do
            table.insert(parts, LiveState.LastScripts[i])
        end
        lastStr = table.concat(parts, " ▸ ")
    end
    LiveLastLbl.Text = "Last 5  : <i>" .. lastStr:sub(1, 55) .. "</i>"

    if LiveState.Total > 0 then
        LiveBarFill.Size = UDim2.new(math.min(1, LiveState.Index / LiveState.Total), 0, 1, 0)
    else
        LiveBarFill.Size = UDim2.new(0, 0, 1, 0)
    end

    if idle > CONFIG.SCAN_WATCHDOG_S then
        LiveWatchdogLbl.Text = string.format("⏱ STUCK %ds — script mungkin hang!", math.floor(idle))
    elseif idle > 3 then
        LiveWatchdogLbl.Text = string.format("⏳ processing %ds...", math.floor(idle))
    else
        LiveWatchdogLbl.Text = ""
    end

    if memMB > CONFIG.SCAN_MEM_FLUSH_MB then
        LMStroke.Color = CONFIG.THEME.Warning
    else
        LMStroke.Color = CONFIG.THEME.Live
    end
end

task.spawn(function()
    while Screen.Parent do
        pcall(updateLiveDisplay)
        task.wait(0.2)
    end
end)

-- Service picker
local SvcLbl = Instance.new("TextLabel", ScanPage)
SvcLbl.Size = UDim2.new(1, 0, 0, 18)
SvcLbl.BackgroundTransparency = 1
SvcLbl.Text = "  🎯 Pilih Service:"
SvcLbl.TextColor3 = CONFIG.THEME.Accent
SvcLbl.Font = Enum.Font.GothamBold
SvcLbl.TextSize = 11
SvcLbl.TextXAlignment = Enum.TextXAlignment.Left

for _, sName in ipairs(CONFIG.ALL_SERVICES) do
    local b = Instance.new("TextButton", ScanPage)
    b.Size = UDim2.new(1, 0, 0, 24)
    b.Text = "  [✓] " .. sName
    b.BackgroundColor3 = CONFIG.THEME.CardBg
    b.BackgroundTransparency = .3
    b.TextColor3 = CONFIG.THEME.Success
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 10
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)

    b.MouseButton1Click:Connect(function()
        Settings.SelectedServices[sName] = not Settings.SelectedServices[sName]
        if Settings.SelectedServices[sName] then
            b.Text = "  [✓] " .. sName
            b.TextColor3 = CONFIG.THEME.Success
        else
            b.Text = "  [ ] " .. sName
            b.TextColor3 = CONFIG.THEME.TextMuted
        end
    end)
end

local QuickBtn = Instance.new("TextButton", ScanPage)
QuickBtn.Size = UDim2.new(1, 0, 0, 28)
QuickBtn.Text = "⚡ Quick Scan (ReplicatedStorage only)"
QuickBtn.BackgroundColor3 = CONFIG.THEME.CardBg
QuickBtn.TextColor3 = CONFIG.THEME.Accent
QuickBtn.Font = Enum.Font.GothamBold
QuickBtn.TextSize = 10
QuickBtn.AutoButtonColor = false
Instance.new("UICorner", QuickBtn).CornerRadius = UDim.new(0, 4)

-- ═══════════════════════════════════════════════════════════
-- REMOTE TAB — Log Display
-- ═══════════════════════════════════════════════════════════
local FilterBar = Instance.new("Frame", RemotePage)
FilterBar.Size = UDim2.new(1, 0, 0, 26)
FilterBar.BackgroundColor3 = CONFIG.THEME.CardBg
FilterBar.BackgroundTransparency = .3
Instance.new("UICorner", FilterBar).CornerRadius = UDim.new(0, 4)

local SearchBox = Instance.new("TextBox", FilterBar)
SearchBox.Size = UDim2.new(0.4, -6, 1, -6)
SearchBox.Position = UDim2.new(0, 6, 0, 3)
SearchBox.BackgroundTransparency = 1
SearchBox.Text = ""
SearchBox.PlaceholderText = "🔍 cari..."
SearchBox.PlaceholderColor3 = CONFIG.THEME.TextMuted
SearchBox.TextColor3 = CONFIG.THEME.TextWhite
SearchBox.Font = Enum.Font.GothamMedium
SearchBox.TextSize = 10
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus = false
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    State.Filter.search = SearchBox.Text:lower()
end)

local ChipHolder = Instance.new("Frame", FilterBar)
ChipHolder.Size = UDim2.new(0.6, -6, 1, 0)
ChipHolder.Position = UDim2.new(0.4, 3, 0, 0)
ChipHolder.BackgroundTransparency = 1
local ChipLayout = Instance.new("UIListLayout", ChipHolder)
ChipLayout.FillDirection = Enum.FillDirection.Horizontal
ChipLayout.Padding = UDim.new(0, 3)
ChipLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local function makeChip(text, color, keyName)
    local chip = Instance.new("TextButton", ChipHolder)
    chip.Size = UDim2.new(0, 55, 0, 20)
    chip.BackgroundColor3 = color
    chip.BackgroundTransparency = .2
    chip.Text = text
    chip.TextColor3 = CONFIG.THEME.TextWhite
    chip.Font = Enum.Font.GothamBold
    chip.TextSize = 9
    chip.AutoButtonColor = false
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 3)
    chip.MouseButton1Click:Connect(function()
        State.Filter[keyName] = not State.Filter[keyName]
        TweenService:Create(chip, TweenInfo.new(.25), {
            BackgroundTransparency = State.Filter[keyName] and .2 or .85
        }):Play()
    end)
end
makeChip("OUT", CONFIG.THEME.Out, "showOut")
makeChip("IN", CONFIG.THEME.Inbound, "showIn")
makeChip("SCAN", CONFIG.THEME.Scan, "showScan")

local Scroll = Instance.new("ScrollingFrame", RemotePage)
Scroll.Size = UDim2.new(1, 0, 1, -32)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 3
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.ScrollBarImageColor3 = CONFIG.THEME.Accent
pcall(function() Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
local SLayout = Instance.new("UIListLayout", Scroll)
SLayout.Padding = UDim.new(0, 5)
SLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ═══════════════════════════════════════════════════════════
-- EXPORT TAB
-- ═══════════════════════════════════════════════════════════
local ExpInfo = Instance.new("TextLabel", ExpPage)
ExpInfo.Size = UDim2.new(1, 0, 0, 80)
ExpInfo.BackgroundColor3 = CONFIG.THEME.CardBg
ExpInfo.BackgroundTransparency = .3
ExpInfo.Text = "  📤 KIRIM KE WEBHOOK DISCORD\n\n  Semua data scan + remote log dikemas dalam 1 file .lua\n  Nama file: NamaGame_NamaPlayer.lua"
ExpInfo.TextColor3 = CONFIG.THEME.TextMuted
ExpInfo.Font = Enum.Font.GothamMedium
ExpInfo.TextSize = 10
ExpInfo.TextWrapped = true
ExpInfo.TextXAlignment = Enum.TextXAlignment.Left
ExpInfo.TextYAlignment = Enum.TextYAlignment.Top
Instance.new("UICorner", ExpInfo).CornerRadius = UDim.new(0, 5)
local EPad = Instance.new("UIPadding", ExpInfo)
EPad.PaddingTop = UDim.new(0, 6)
EPad.PaddingLeft = UDim.new(0, 8)
EPad.PaddingRight = UDim.new(0, 8)

local ExpInfoStat = Instance.new("TextLabel", ExpPage)
ExpInfoStat.Size = UDim2.new(1, 0, 0, 60)
ExpInfoStat.BackgroundColor3 = CONFIG.THEME.CardBg
ExpInfoStat.BackgroundTransparency = .3
ExpInfoStat.Text = ""
ExpInfoStat.TextColor3 = CONFIG.THEME.Success
ExpInfoStat.Font = Enum.Font.Code
ExpInfoStat.TextSize = 10
ExpInfoStat.TextWrapped = true
ExpInfoStat.TextXAlignment = Enum.TextXAlignment.Left
ExpInfoStat.TextYAlignment = Enum.TextYAlignment.Top
Instance.new("UICorner", ExpInfoStat).CornerRadius = UDim.new(0, 5)
local ESPad = Instance.new("UIPadding", ExpInfoStat)
ESPad.PaddingTop = UDim.new(0, 6)
ESPad.PaddingLeft = UDim.new(0, 8)

task.spawn(function()
    while Screen.Parent do
        pcall(function()
            local totalSections = 0
            local totalBytes = 0
            for _, content in pairs(State.LastDump) do
                totalSections = totalSections + 1
                totalBytes = totalBytes + #content
            end
            ExpInfoStat.Text = string.format(
                "  📊 Status:\n  • Sections : %d\n  • Total Size: %.1f KB\n  • Remote Logs: %d",
                totalSections, totalBytes / 1024, #State.Logs
            )
        end)
        task.wait(1)
    end
end)

local ExpBtn = Instance.new("TextButton", ExpPage)
ExpBtn.Size = UDim2.new(1, 0, 0, 36)
ExpBtn.Text = "📤 SEND TO WEBHOOK"
ExpBtn.BackgroundColor3 = CONFIG.THEME.Accent
ExpBtn.TextColor3 = CONFIG.THEME.TextWhite
ExpBtn.Font = Enum.Font.GothamBold
ExpBtn.TextSize = 11
ExpBtn.AutoButtonColor = false
Instance.new("UICorner", ExpBtn).CornerRadius = UDim.new(0, 5)

local ExpClearBtn = Instance.new("TextButton", ExpPage)
ExpClearBtn.Size = UDim2.new(1, 0, 0, 28)
ExpClearBtn.Text = "🗑 CLEAR SCAN DATA"
ExpClearBtn.BackgroundColor3 = CONFIG.THEME.Warning
ExpClearBtn.TextColor3 = CONFIG.THEME.TextWhite
ExpClearBtn.Font = Enum.Font.GothamBold
ExpClearBtn.TextSize = 10
ExpClearBtn.AutoButtonColor = false
Instance.new("UICorner", ExpClearBtn).CornerRadius = UDim.new(0, 4)

-- ═══════════════════════════════════════════════════════════
-- SETTINGS TAB
-- ═══════════════════════════════════════════════════════════
local function makeSettingToggle(name, defaultVal, callback)
    local b = Instance.new("TextButton", SetPage)
    b.Size = UDim2.new(1, 0, 0, 32)
    b.Text = "  " .. name .. ": " .. (defaultVal and "ON" or "OFF")
    b.BackgroundColor3 = CONFIG.THEME.CardBg
    b.BackgroundTransparency = .3
    b.TextColor3 = defaultVal and CONFIG.THEME.Success or CONFIG.THEME.TextMuted
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.AutoButtonColor = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)

    b.MouseButton1Click:Connect(function()
        local newVal = callback()
        b.Text = "  " .. name .. ": " .. (newVal and "ON" or "OFF")
        b.TextColor3 = newVal and CONFIG.THEME.Success or CONFIG.THEME.TextMuted
    end)
end

makeSettingToggle("Skip Internal Scripts", Settings.SkipInternal, function()
    Settings.SkipInternal = not Settings.SkipInternal
    return Settings.SkipInternal
end)

makeSettingToggle("Deep Scan", Settings.DeepScanEnabled, function()
    Settings.DeepScanEnabled = not Settings.DeepScanEnabled
    return Settings.DeepScanEnabled
end)

-- Delay slider (pakai button cycle)
local delayOptions = {0.05, 0.08, 0.1, 0.15, 0.2, 0.3, 0.5}
local delayIndex = 2
local delayBtn = Instance.new("TextButton", SetPage)
delayBtn.Size = UDim2.new(1, 0, 0, 32)
delayBtn.Text = "  ⏱ Scan Delay: " .. delayOptions[delayIndex] .. "s"
delayBtn.BackgroundColor3 = CONFIG.THEME.CardBg
delayBtn.BackgroundTransparency = .3
delayBtn.TextColor3 = CONFIG.THEME.Accent
delayBtn.Font = Enum.Font.GothamBold
delayBtn.TextSize = 10
delayBtn.TextXAlignment = Enum.TextXAlignment.Left
delayBtn.AutoButtonColor = false
Instance.new("UICorner", delayBtn).CornerRadius = UDim.new(0, 5)
delayBtn.MouseButton1Click:Connect(function()
    delayIndex = (delayIndex % #delayOptions) + 1
    Settings.ScanDelay = delayOptions[delayIndex]
    delayBtn.Text = "  ⏱ Scan Delay: " .. Settings.ScanDelay .. "s"
end)

-- Info box
local InfoBox = Instance.new("TextLabel", SetPage)
InfoBox.Size = UDim2.new(1, 0, 0, 80)
InfoBox.BackgroundColor3 = CONFIG.THEME.CardBg
InfoBox.BackgroundTransparency = .5
InfoBox.Text = "  ℹ️ INFO\n\n  Skip Internal: memblokir RbxCharacterSounds dll\n  Deep Scan: reference following (lebih lambat)\n  Delay: turunin kalau HP kamu kuat"
InfoBox.TextColor3 = CONFIG.THEME.TextMuted
InfoBox.Font = Enum.Font.GothamMedium
InfoBox.TextSize = 9
InfoBox.TextWrapped = true
InfoBox.TextXAlignment = Enum.TextXAlignment.Left
InfoBox.TextYAlignment = Enum.TextYAlignment.Top
Instance.new("UICorner", InfoBox).CornerRadius = UDim.new(0, 5)
local IPad = Instance.new("UIPadding", InfoBox)
IPad.PaddingTop = UDim.new(0, 6)
IPad.PaddingLeft = UDim.new(0, 8)

-- ═══════════════════════════════════════════════════════════
-- LOG RENDER
-- ═══════════════════════════════════════════════════════════
local function passFilter(entry)
    if entry.Type == "OUT"    and not State.Filter.showOut  then return false end
    if entry.Type == "IN"     and not State.Filter.showIn   then return false end
    if entry.Type == "SCAN"   and not State.Filter.showScan then return false end
    if State.Filter.search ~= "" then
        local needle = State.Filter.search
        local hay = (entry.Name .. " " .. (entry.ArgsPlain or "") .. " " .. (entry.Path or "")):lower()
        if not hay:find(needle, 1, true) then return false end
    end
    return true
end

local function addLogUI(entry)
    if not passFilter(entry) then return end
    local children = Scroll:GetChildren()
    local count = 0
    for _, c in ipairs(children) do
        if c:IsA("Frame") then count = count + 1 end
    end
    if count > CONFIG.MAX_LOGS then
        for _, c in ipairs(children) do
            if c:IsA("Frame") then c:Destroy() break end
        end
    end

    local frame = Instance.new("Frame", Scroll)
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.BackgroundColor3 = CONFIG.THEME.CardBg
    frame.BackgroundTransparency = .2
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 5)
    local pad = Instance.new("UIPadding", frame)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pcall(function() frame.AutomaticSize = Enum.AutomaticSize.Y end)

    local accent = Instance.new("Frame", frame)
    accent.Size = UDim2.new(0, 3, 1, -8)
    accent.Position = UDim2.new(0, 0, 0, 4)
    local acColor =
        entry.Type == "IN"     and CONFIG.THEME.Inbound or
        entry.Type == "SCAN"   and CONFIG.THEME.Scan    or
        CONFIG.THEME.Out
    accent.BackgroundColor3 = acColor
    accent.BorderSizePixel = 0
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(1, -16, 0, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.RichText = true
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 9
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    pcall(function() lbl.AutomaticSize = Enum.AutomaticSize.Y end)

    local typeColor =
        entry.Type == "IN"     and "#FF4C60" or
        entry.Type == "SCAN"   and "#B450FF" or
        "#00E1FF"

    lbl.Text = string.format(
        "<font color='#666677'>[%s]</font> <font color='%s'><b>%s</b></font> <font color='#FFFFFF'>%s</font>%s\n" ..
        "<font color='#888899'>→</font> <font color='#DCD6F7'>%s</font>",
        entry.Time, typeColor, entry.Type, entry.Name,
        entry.CallCount and entry.CallCount > 1 and (" <font color='#FFD700'>(x" .. entry.CallCount .. ")</font>") or "",
        entry.ArgsUI ~= "" and entry.ArgsUI or entry.Path
    )
    entry.UILabel = lbl

    task.defer(function()
        task.wait(0.05)
        local layout = Scroll:FindFirstChildOfClass("UIListLayout")
        if layout then
            Scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 15)
        end
        Scroll.CanvasPosition = Vector2.new(0, Scroll.CanvasSize.Y.Offset)
    end)
end

local gcCounter = 0
table.insert(State.Connections, RunService.Heartbeat:Connect(function()
    local processed = 0
    while #State.RawBuffer > 0 and processed < 15 do
        processed = processed + 1
        local item = table.remove(State.RawBuffer, 1)

        local shouldProcess = false
        if item.Type == "SCAN" then
            shouldProcess = true
        elseif item.Type == "OUT" then
            shouldProcess = not State.isIgnoredOut(tostring(item.Obj))
        elseif item.Type == "IN" then
            shouldProcess = not State.isIgnoredIn(tostring(item.Obj))
        end

        if shouldProcess then
            State.TotalCalls = State.TotalCalls + 1
            local last = State.Logs[#State.Logs]
            if last and last.Name == tostring(item.Obj) and last.Type == item.Type and not last.UILabel then
                last.CallCount = (last.CallCount or 1) + 1
                last.Time = item.Time
            else
                local entry = {
                    Time      = item.Time,
                    Type      = item.Type,
                    Path      = getInstancePath(item.Obj),
                    Name      = tostring(item.Obj),
                    ArgsLua   = formatArgsPlain(item.Args),
                    ArgsUI    = formatArgs(item.Args),
                    ArgsPlain = formatArgsPlain(item.Args),
                    Method    = item.Method,
                    Caller    = item.Caller,
                    CallCount = 1,
                    UILabel   = nil,
                }
                table.insert(State.Logs, entry)
                table.insert(State.LogQueue, entry)
            end
        end
    end

    for _ = 1, math.min(2, #State.LogQueue) do
        pcall(addLogUI, table.remove(State.LogQueue, 1))
    end

    gcCounter = gcCounter + 1
    if gcCounter >= 300 then
        gcCounter = 0
        pcall(function() collectgarbage("step") end)
    end
end))

-- ═══════════════════════════════════════════════════════════
-- HOOKS
-- ═══════════════════════════════════════════════════════════
do
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then error("getrawmetatable nil") end
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if State.RecOut and (method == "FireServer" or method == "InvokeServer") then
                if not State.isIgnoredOut(tostring(self)) and #State.RawBuffer < 1000 then
                    table.insert(State.RawBuffer, {
                        Time = getPreciseTime(), Type = "OUT", Obj = self,
                        Args = {...}, Method = method, Caller = "Client",
                    })
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if not ok then warn("[Mizukage] __namecall hook gagal: " .. tostring(err)) end
end

local function hookRemote(remote)
    if not remote:IsA("RemoteEvent") then return end
    if State.HookedRemotes[remote] then return end
    State.HookedRemotes[remote] = true
    pcall(function()
        table.insert(State.Connections, remote.OnClientEvent:Connect(function(...)
            if State.RecIn and #State.RawBuffer < 1000 then
                table.insert(State.RawBuffer, {
                    Time = getPreciseTime(), Type = "IN", Obj = remote,
                    Args = {...}, Method = "OnClientEvent", Caller = "Server",
                })
            end
        end))
    end)
end

local function hookRemoteFunction(rf)
    if not rf:IsA("RemoteFunction") then return end
    if State.HookedRemotes[rf] then return end
    State.HookedRemotes[rf] = true
    pcall(function()
        local old = rf.OnClientInvoke
        rf.OnClientInvoke = function(...)
            if State.RecIn and #State.RawBuffer < 1000 then
                table.insert(State.RawBuffer, {
                    Time = getPreciseTime(), Type = "IN", Obj = rf,
                    Args = {...}, Method = "OnClientInvoke", Caller = "Server-RF",
                })
            end
            if old then return old(...) end
        end
    end)
end

for _, obj in ipairs(game:GetDescendants()) do
    pcall(function()
        if obj:IsA("RemoteEvent") then hookRemote(obj)
        elseif obj:IsA("RemoteFunction") then hookRemoteFunction(obj) end
    end)
end

table.insert(State.Connections, game.DescendantAdded:Connect(function(obj)
    pcall(function()
        if obj:IsA("RemoteEvent") then hookRemote(obj)
        elseif obj:IsA("RemoteFunction") then hookRemoteFunction(obj) end
    end)
end))

-- ═══════════════════════════════════════════════════════════
-- BUTTONS
-- ═══════════════════════════════════════════════════════════
BtnOut.MouseButton1Click:Connect(function()
    State.RecOut = not State.RecOut
    BtnOut.Text = State.RecOut and "OUT✓" or "OUT"
    BtnOut.TextColor3 = State.RecOut and CONFIG.THEME.Out or CONFIG.THEME.TextWhite
end)

BtnIn.MouseButton1Click:Connect(function()
    State.RecIn = not State.RecIn
    BtnIn.Text = State.RecIn and "IN✓" or "IN"
    BtnIn.TextColor3 = State.RecIn and CONFIG.THEME.Inbound or CONFIG.THEME.TextWhite
end)

BtnClear.MouseButton1Click:Connect(function()
    State.Logs = {}; State.LogQueue = {}; State.RawBuffer = {}; State.TotalCalls = 0
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    pcall(function() collectgarbage("collect") end)
    getgenv().MizuNotify("🗑 CLEARED", "Log dihapus.", CONFIG.THEME.Clear, 2)
end)

BtnStop.MouseButton1Click:Connect(function()
    if State.ScanRunning then
        State.ScanAbort = true
        getgenv().MizuNotify("⏹ STOP", "Scan dibatalkan...", CONFIG.THEME.Warning, 3)
    end
end)

ExpClearBtn.MouseButton1Click:Connect(function()
    State.LastDump = {}
    getgenv().MizuNotify("🗑 CLEARED", "Data scan dihapus.", CONFIG.THEME.Clear, 2)
end)

-- ═══════════════════════════════════════════════════════════
-- SCAN ENGINE v7.0
-- ═══════════════════════════════════════════════════════════
local function shouldSkipScript(obj)
    if not Settings.SkipInternal then return false, "" end
    local name = obj.Name
    for _, skipName in ipairs(CONFIG.SKIP_NAMES) do
        if name == skipName or name:find(skipName, 1, true) then
            return true, "name:" .. skipName
        end
    end
    local path = ""
    pcall(function() path = obj:GetFullName() end)
    for _, skipPath in ipairs(CONFIG.SKIP_PATHS) do
        if path:find(skipPath, 1, true) then
            return true, "path:" .. skipPath
        end
    end
    return false, ""
end

local function getSelectedServices()
    local list = {}
    for _, sName in ipairs(CONFIG.ALL_SERVICES) do
        if Settings.SelectedServices[sName] then
            table.insert(list, sName)
        end
    end
    return list
end

local function RunScan(services)
    if State.ScanRunning then
        getgenv().MizuNotify("⚠ SIBUK", "Scan sedang berjalan.", CONFIG.THEME.Warning, 3)
        return
    end
    if not decompileFn then
        getgenv().MizuNotify("SCAN GAGAL", "Executor tidak support decompile.", CONFIG.THEME.Warning, 5)
        return
    end

    State.ScanRunning = true
    State.ScanAbort = false
    LiveState.StartTime = os.clock()
    LiveState.LastProgress = os.clock()
    LiveState.LastScripts = {}
    LiveState.Success = 0
    LiveState.Fail = 0
    LiveState.Skipped = 0
    LiveState.Internal = 0
    LiveState.Big = 0
    LiveState.Index = 0
    LiveState.Total = 0

    getgenv().MizuNotify("🚀 SCAN v7.0",
        #services .. " service • internal-skip ON",
        CONFIG.THEME.Live, 4)

    task.spawn(function()
        local totalScripts = 0
        local successCount = 0
        local failCount = 0
        local skippedCount = 0
        local internalCount = 0
        local bigCount = 0
        local startClock = os.clock()

        State.LastDump = {}
        local scanned = {}

        for _, serviceName in ipairs(services) do
            if State.ScanAbort then break end

            LiveState.Service = serviceName
            LiveState.Index = 0
            LiveState.Total = 0
            LiveState.LastProgress = os.clock()

            local svc = safeGetService(serviceName)
            if svc then
                local allScripts = {}
                pcall(function()
                    local count = 0
                    for _, obj in ipairs(svc:GetDescendants()) do
                        if obj:IsA("LuaSourceContainer") and not scanned[obj] then
                            table.insert(allScripts, obj)
                            scanned[obj] = true
                            count = count + 1
                            if count >= CONFIG.SCAN_MAX_PER_SVC then break end
                        end
                    end
                end)

                LiveState.Total = #allScripts
                local svcChunks = {}

                for i = 1, #allScripts do
                    if State.ScanAbort then break end
                    local obj = allScripts[i]

                    LiveState.Index = i
                    LiveState.Name = obj.Name
                    LiveState.Size = 0
                    LiveState.LastProgress = os.clock()
                    pushLastScript(obj.Name)

                    -- SKIP CHECK
                    local skip, reason = shouldSkipScript(obj)
                    if skip then
                        internalCount = internalCount + 1
                        LiveState.Internal = internalCount
                        totalScripts = totalScripts + 1
                        svcChunks[#svcChunks + 1] = string.format(
                            "\n-- [INTERNAL SKIP] %s\n-- Path: %s\n-- Reason: %s\n\n",
                            obj.Name, getInstancePath(obj), reason
                        )
                        task.wait(0.03)
                    else
                        local ok = pcall(function()
                            local sType = getScriptType(obj)
                            local path = getInstancePath(obj)

                            local decompOk, result = pcall(decompileFn, obj)
                            local source = (decompOk and type(result) == "string") and result or ""

                            LiveState.Size = #source

                            if #source > CONFIG.SCAN_MAX_SRC_CHUNK then
                                skippedCount = skippedCount + 1
                                bigCount = bigCount + 1
                                LiveState.Skipped = skippedCount
                                LiveState.Big = bigCount
                                svcChunks[#svcChunks + 1] = string.format(
                                    "\n-- [TOO BIG] %s — %s\n-- Path: %s\n-- Size: %d KB\n\n",
                                    sType, obj.Name, path, math.floor(#source / 1024))
                                totalScripts = totalScripts + 1
                                return
                            end

                            if source ~= "" and #source >= CONFIG.SCAN_MIN_SRC_LEN
                            and not source:find("failed to decompile")
                            and not source:find("Too Many Requests") then
                                successCount = successCount + 1
                                LiveState.Success = successCount
                                svcChunks[#svcChunks + 1] = string.format(
                                    "\n-- ═══════════════════════════════════════\n" ..
                                    "-- [%s] %s\n-- Path: %s\n-- Size: %d KB\n-- ═══════════════════════════════════════\n%s\n",
                                    sType, obj.Name, path, math.floor(#source / 1024), source
                                )
                            else
                                failCount = failCount + 1
                                LiveState.Fail = failCount
                                svcChunks[#svcChunks + 1] = string.format(
                                    "\n-- [FAILED] %s — %s\n-- Path: %s\n",
                                    sType, obj.Name, path)
                            end
                            totalScripts = totalScripts + 1
                        end)
                        if not ok then
                            failCount = failCount + 1
                            LiveState.Fail = failCount
                            totalScripts = totalScripts + 1
                        end
                    end

                    -- Flush
                    if i % CONFIG.SCAN_FLUSH_EVERY == 0 and #svcChunks > 0 then
                        local combined = table.concat(svcChunks, "")
                        svcChunks = { combined }
                        pcall(function() collectgarbage("step") end)
                    end

                    task.wait(Settings.ScanDelay)

                    if i % CONFIG.SCAN_GC_EVERY == 0 then
                        pcall(function() collectgarbage("step") end)
                    end
                    if i % CONFIG.SCAN_HARD_GC_EVERY == 0 then
                        pcall(function() collectgarbage("collect") end)
                        task.wait(0.2)
                    end
                end

                if #svcChunks > 0 then
                    State.LastDump[serviceName] = table.concat(svcChunks, "")
                end
                svcChunks = nil
                allScripts = nil
                pcall(function() collectgarbage("collect") end)
                task.wait(0.3)
            end
        end

        -- Deep scan
        if Settings.DeepScanEnabled and not State.ScanAbort then
            LiveState.Service = "DEEP"
            LiveState.Name = "building..."
            LiveState.LastProgress = os.clock()

            local pool = {}
            local pathIndex = {}
            for _, svcName in ipairs(services) do
                local svc = safeGetService(svcName)
                if svc then
                    pcall(function()
                        for _, obj in ipairs(svc:GetDescendants()) do
                            if obj:IsA("LuaSourceContainer") then
                                local lower = obj.Name:lower()
                                pool[lower] = pool[lower] or {}
                                table.insert(pool[lower], obj)
                                pathIndex[obj:GetFullName():lower()] = obj
                            end
                        end
                    end)
                end
                task.wait(0.1)
            end

            LiveState.Name = "refs..."
            local refs = {}
            for _, content in pairs(State.LastDump) do
                if type(content) == "string" and #content < 200 * 1024 then
                    for word in content:gmatch("[%a_][%w_]*") do
                        if #word >= 4 and #word <= 64 then
                            refs[word:lower()] = true
                        end
                    end
                end
                task.wait(0.05)
            end

            LiveState.Name = "match..."
            local newTargets = {}
            local iter = 0
            for refLower in pairs(refs) do
                iter = iter + 1
                if iter % 100 == 0 then task.wait(0.05) end
                local candidates = pool[refLower]
                if candidates then
                    for _, cand in ipairs(candidates) do
                        if not scanned[cand] then
                            scanned[cand] = true
                            table.insert(newTargets, cand)
                            if #newTargets >= CONFIG.DEEP_SCAN_MAX_TARGET then break end
                        end
                    end
                end
                if #newTargets >= CONFIG.DEEP_SCAN_MAX_TARGET then break end
            end
            refs = nil; pool = nil; pathIndex = nil
            pcall(function() collectgarbage("collect") end)

            if #newTargets > 0 then
                LiveState.Total = #newTargets
                LiveState.Index = 0
                local deepChunks = { "\n-- ═══ DEEP SCAN ═══\n" }
                for i = 1, #newTargets do
                    if State.ScanAbort then break end
                    local obj = newTargets[i]
                    LiveState.Index = i
                    LiveState.Name = obj.Name
                    LiveState.LastProgress = os.clock()
                    pushLastScript(obj.Name)

                    local skip = shouldSkipScript(obj)
                    if skip then
                        internalCount = internalCount + 1
                        LiveState.Internal = internalCount
                        deepChunks[#deepChunks + 1] = "-- [INTERNAL] " .. obj.Name .. "\n"
                    else
                        pcall(function()
                            local sType = getScriptType(obj)
                            local path = getInstancePath(obj)
                            local decompOk, result = pcall(decompileFn, obj)
                            local source = (decompOk and type(result) == "string") and result or ""
                            LiveState.Size = #source
                            if #source > 500 * 1024 then
                                deepChunks[#deepChunks + 1] = "-- [TOO BIG] " .. obj.Name .. "\n"
                                return
                            end
                            if source ~= "" and not source:find("failed to decompile") then
                                successCount = successCount + 1
                                LiveState.Success = successCount
                                deepChunks[#deepChunks + 1] = string.format(
                                    "\n-- [DEEP] %s — %s\n-- Path: %s\n-- ═══\n%s\n",
                                    sType, obj.Name, path, source)
                            end
                            totalScripts = totalScripts + 1
                        end)
                    end
                    task.wait(Settings.ScanDelay)
                end
                State.LastDump["_DEEP_SCAN"] = table.concat(deepChunks, "")
                deepChunks = nil
                newTargets = nil
                pcall(function() collectgarbage("collect") end)
            end
        end

        local elapsed = os.clock() - startClock
        if State.ScanAbort then
            getgenv().MizuNotify("⏹ STOPPED",
                string.format("%d scripts • %.1fs", totalScripts, elapsed),
                CONFIG.THEME.Warning, 5)
        else
            getgenv().MizuNotify("🎉 SCAN SELESAI",
                string.format("%d✓ %d✗ %d internal %d big • %.1fs",
                    successCount, failCount, internalCount, bigCount, elapsed),
                CONFIG.THEME.Success, 6)
        end

        State.ScanRunning = false
        State.ScanAbort = false
        pcall(function() collectgarbage("collect") end)
    end)
end

BtnScan.MouseButton1Click:Connect(function()
    local list = getSelectedServices()
    if #list == 0 then
        getgenv().MizuNotify("⚠ KOSONG", "Pilih minimal 1 service.", CONFIG.THEME.Warning, 3)
        return
    end
    RunScan(list)
end)

QuickBtn.MouseButton1Click:Connect(function()
    RunScan({"ReplicatedStorage"})
end)

-- ═══════════════════════════════════════════════════════════
-- EXPORT
-- ═══════════════════════════════════════════════════════════
ExpBtn.MouseButton1Click:Connect(function()
    if WEBHOOK_URL == "" or not WEBHOOK_URL:match("^https://discord%.com/api/webhooks/") then
        getgenv().MizuNotify("EXP GAGAL", "Webhook kosong.", CONFIG.THEME.Warning, 4)
        return
    end
    if not httpRequest then
        getgenv().MizuNotify("EXP GAGAL", "No HTTP support.", CONFIG.THEME.Warning, 4)
        return
    end

    local hasScan = next(State.LastDump) ~= nil
    local hasLogs = #State.Logs > 0
    if not hasScan and not hasLogs then
        getgenv().MizuNotify("EXP GAGAL", "Belum ada data.", CONFIG.THEME.Warning, 4)
        return
    end

    task.spawn(function()
        local playerName   = LocalPlayer.Name
        local displayName  = LocalPlayer.DisplayName or playerName
        local userId       = LocalPlayer.UserId
        local placeId      = tostring(game.PlaceId)
        local jobId        = tostring(game.JobId or "")
        local timestamp    = os.date("!%Y-%m-%dT%H:%M:%SZ")

        getgenv().MizuNotify("📤 EXPORT", "Ambil avatar...", CONFIG.THEME.Export, 3)
        local avatarUrl = getRobloxAvatar(userId)

        local lines = {}
        table.insert(lines, "╔══════════════════════════════════════════════════════════╗")
        table.insert(lines, "║     MIZUKAGE MONITOR v" .. CONFIG.VERSION .. " — DUMP                     ║")
        table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
        table.insert(lines, "")
        table.insert(lines, "-- ═══ METADATA ═══")
        table.insert(lines, "-- Game Name    : " .. GameName)
        table.insert(lines, "-- Place ID     : " .. placeId)
        table.insert(lines, "-- Job ID       : " .. jobId)
        table.insert(lines, "-- Player       : " .. playerName .. " (" .. displayName .. ")")
        table.insert(lines, "-- User ID      : " .. tostring(userId))
        table.insert(lines, "-- Export Time  : " .. os.date("%Y-%m-%d %H:%M:%S"))
        table.insert(lines, "")

        if hasScan then
            for svcName, content in pairs(State.LastDump) do
                table.insert(lines, "")
                table.insert(lines, "╔══════════════════════════════════════════════════════════╗")
                table.insert(lines, "║  📂 SERVICE: " .. string.format("%-43s", svcName) .. "║")
                table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
                table.insert(lines, "")
                table.insert(lines, content)
                table.insert(lines, "")
                table.insert(lines, "-- ═══ END ═══")
                table.insert(lines, "")
            end
        end

        if hasLogs then
            table.insert(lines, "")
            table.insert(lines, "╔══════════════════════════════════════════════════════════╗")
            table.insert(lines, "║  📡 REMOTE TRAFFIC LOG                                   ║")
            table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
            table.insert(lines, "")
            for _, r in ipairs(State.Logs) do
                table.insert(lines, string.format("-- [%s | %s] %s | %s | x%d",
                    r.Time, r.Type, r.Name, r.Method, r.CallCount or 1))
                table.insert(lines, "-- Path: " .. r.Path)
                table.insert(lines, "local args = " .. (r.ArgsLua or "{}"))
                table.insert(lines, "")
            end
        end

        local packedContent = table.concat(lines, "\n")
        local packedSize = #packedContent
        lines = nil
        pcall(function() collectgarbage("step") end)

        local fileName = string.format("%s_%s.lua",
            safeFileName(GameName), safeFileName(playerName))

        local profileName = displayName .. " | " .. playerName
        local profileAvatar = avatarUrl or "https://cdn.discordapp.com/embed/avatars/0.png"

        local embed = {
            title = "🎯 " .. GameName .. " — " .. displayName,
            description = "**Dump** dari **" .. GameName .. "**\n"
                .. "Target: `" .. playerName .. "` (`" .. userId .. "`)\n"
                .. "Mizukage v" .. CONFIG.VERSION,
            color = 0x00E1FF,
            timestamp = timestamp,
            footer = { text = "Mizukage v" .. CONFIG.VERSION .. " • " .. placeId },
            fields = {
                { name = "🎮 Game", value = "`" .. GameName .. "`", inline = true },
                { name = "👤 Player", value = "`" .. playerName .. "`", inline = true },
                { name = "📦 File", value = "`" .. fileName .. "`" },
                { name = "📊 Size", value = string.format("%.1f KB", packedSize / 1024), inline = true },
                { name = "📡 Logs", value = tostring(#State.Logs), inline = true },
            },
        }
        if avatarUrl then embed.thumbnail = { url = avatarUrl } end

        local boundary = "----MizuBoundary" .. tostring(math.random(100000, 999999))
        local jsonBody = HttpService:JSONEncode({
            username = profileName, avatar_url = profileAvatar, embeds = { embed },
        })

        local body = "--" .. boundary .. "\r\n"
            .. 'Content-Disposition: form-data; name="payload_json"\r\n'
            .. "Content-Type: application/json\r\n\r\n"
            .. jsonBody .. "\r\n"
            .. "--" .. boundary .. "\r\n"
            .. 'Content-Disposition: form-data; name="file"; filename="' .. fileName .. '"\r\n'
            .. "Content-Type: text/plain; charset=utf-8\r\n\r\n"
            .. packedContent .. "\r\n"
            .. "--" .. boundary .. "--\r\n"

        packedContent = nil
        pcall(function() collectgarbage("step") end)

        getgenv().MizuNotify("📤 UPLOAD", fileName .. " (" .. math.floor(packedSize / 1024) .. " KB)",
            CONFIG.THEME.Export, 4)

        local success = false
        for attempt = 1, 3 do
            local ok, res = pcall(function()
                return httpRequest({
                    Url = WEBHOOK_URL, Method = "POST",
                    Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                    Body = body,
                })
            end)
            if ok and res and res.Success then success = true; break
            end
            if attempt < 3 then task.wait(2 + attempt) end
        end

        body = nil
        pcall(function() collectgarbage("collect") end)

        if success then
            getgenv().MizuNotify("✅ EXPORT OK", fileName, CONFIG.THEME.Success, 5)
        else
            getgenv().MizuNotify("❌ EXPORT GAGAL", "Cek webhook/koneksi.", CONFIG.THEME.Warning, 5)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════
-- LOGO MINIMIZE
-- ═══════════════════════════════════════════════════════════
local LogoState = { active = false, logoObj = nil, pulseConn = nil, ringAngle = 0, ringConn = nil }

local function cleanupLogo()
    if LogoState.pulseConn then pcall(function() LogoState.pulseConn:Disconnect() end); LogoState.pulseConn = nil end
    if LogoState.ringConn then pcall(function() LogoState.ringConn:Disconnect() end); LogoState.ringConn = nil end
end

local function createCoolLogo()
    if LogoState.logoObj then pcall(function() LogoState.logoObj:Destroy() end) end
    cleanupLogo()
    local existing = Screen:FindFirstChild("MizuLogo")
    if existing then pcall(function() existing:Destroy() end) end

    local LogoRoot = Instance.new("Frame", Screen)
    LogoRoot.Name = "MizuLogo"
    LogoRoot.Size = UDim2.new(0, 58, 0, 58)
    LogoRoot.Position = UDim2.new(0, 18, 0, 18)
    LogoRoot.BackgroundTransparency = 1
    LogoRoot.ZIndex = 20
    LogoRoot.Active = true
    LogoState.logoObj = LogoRoot

    local Ring = Instance.new("Frame", LogoRoot)
    Ring.Size = UDim2.new(1, 8, 1, 8)
    Ring.Position = UDim2.new(0, -4, 0, -4)
    Ring.BackgroundTransparency = 1
    Ring.BorderSizePixel = 0
    Ring.ZIndex = 20
    Instance.new("UICorner", Ring).CornerRadius = UDim.new(1, 0)
    local RingStroke = Instance.new("UIStroke", Ring)
    RingStroke.Thickness = 2
    local RingGradient = Instance.new("UIGradient", RingStroke)
    RingGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CONFIG.THEME.Accent),
        ColorSequenceKeypoint.new(0.33, CONFIG.THEME.Scan),
        ColorSequenceKeypoint.new(0.66, CONFIG.THEME.Success),
        ColorSequenceKeypoint.new(1, CONFIG.THEME.Accent),
    })

    local Glow = Instance.new("Frame", LogoRoot)
    Glow.Size = UDim2.new(1, 12, 1, 12)
    Glow.Position = UDim2.new(0, -6, 0, -6)
    Glow.BackgroundColor3 = CONFIG.THEME.Accent
    Glow.BackgroundTransparency = 0.75
    Glow.BorderSizePixel = 0
    Glow.ZIndex = 19
    Instance.new("UICorner", Glow).CornerRadius = UDim.new(1, 0)

    local LogoBody = Instance.new("TextButton", LogoRoot)
    LogoBody.Size = UDim2.new(1, 0, 1, 0)
    LogoBody.BackgroundColor3 = CONFIG.THEME.BgBase
    LogoBody.Text = ""
    LogoBody.AutoButtonColor = false
    LogoBody.ZIndex = 21
    LogoBody.Active = true
    Instance.new("UICorner", LogoBody).CornerRadius = UDim.new(1, 0)

    local BodyStroke = Instance.new("UIStroke", LogoBody)
    BodyStroke.Color = CONFIG.THEME.Accent
    BodyStroke.Thickness = 1.5
    BodyStroke.Transparency = 0.3

    local LogoImage = Instance.new("ImageLabel", LogoBody)
    LogoImage.Size = UDim2.new(1, -8, 1, -8)
    LogoImage.Position = UDim2.new(0, 4, 0, 4)
    LogoImage.BackgroundTransparency = 1
    LogoImage.Image = CONFIG.LOGO_IMAGE
    LogoImage.ZIndex = 22
    LogoImage.ScaleType = Enum.ScaleType.Fit
    Instance.new("UICorner", LogoImage).CornerRadius = UDim.new(1, 0)

    local FallbackText = Instance.new("TextLabel", LogoBody)
    FallbackText.Size = UDim2.new(1, 0, 1, 0)
    FallbackText.BackgroundTransparency = 1
    FallbackText.Text = CONFIG.LOGO_FALLBACK_TEXT
    FallbackText.TextColor3 = CONFIG.THEME.Accent
    FallbackText.Font = Enum.Font.GothamBlack
    FallbackText.TextSize = 24
    FallbackText.Visible = false
    FallbackText.ZIndex = 22

    LogoImage:GetPropertyChangedSignal("IsLoaded"):Connect(function()
        if not LogoImage.IsLoaded and LogoImage.Image ~= "" then
            task.wait(2)
            if not LogoImage.IsLoaded then
                FallbackText.Visible = true
                LogoImage.Visible = false
            end
        end
    end)

    LogoState.active = true
    LogoState.ringAngle = 0

    local pulseTime = 0
    LogoState.pulseConn = RunService.Heartbeat:Connect(function(dt)
        pulseTime = pulseTime + dt
        local pulse = (math.sin(pulseTime * 3) + 1) / 2
        pcall(function()
            Glow.BackgroundTransparency = 0.55 + (pulse * 0.3)
            Glow.Size = UDim2.new(1, 10 + (pulse * 8), 1, 10 + (pulse * 8))
            Glow.Position = UDim2.new(0, -5 - (pulse * 4), 0, -5 - (pulse * 4))
            BodyStroke.Transparency = 0.5 - (pulse * 0.35)
        end)
    end)

    LogoState.ringConn = RunService.Heartbeat:Connect(function(dt)
        LogoState.ringAngle = (LogoState.ringAngle + dt * 90) % 360
        pcall(function() RingGradient.Rotation = LogoState.ringAngle end)
    end)

    makeDraggable(LogoRoot, LogoBody)

    LogoBody.MouseButton1Click:Connect(function()
        Main.Visible = true
        Main.Size = UDim2.new(0, 100, 0, 80)
        Main.BackgroundTransparency = 1
        MainStroke.Transparency = 1
        TweenService:Create(Main, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 460, 0, 400),
            BackgroundTransparency = .08
        }):Play()
        TweenService:Create(MainStroke, TweenInfo.new(.4), { Transparency = 0 }):Play()
        task.wait(0.4)
        cleanupLogo()
        LogoState.active = false
        LogoState.logoObj = nil
        pcall(function() LogoRoot:Destroy() end)
    end)

    LogoBody.MouseButton2Click:Connect(function()
        task.wait(0.2)
        State.ScanAbort = true
        for _, c in ipairs(State.Connections) do
            pcall(function() c:Disconnect() end)
        end
        getgenv().MizuMonitorActive = false
        getgenv().MizuNotify = nil
        cleanupLogo()
        Screen:Destroy()
    end)

    LogoRoot.Size = UDim2.new(0, 0, 0, 0)
    TweenService:Create(LogoRoot, TweenInfo.new(.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 58, 0, 58)
    }):Play()
end

BtnMin.MouseButton1Click:Connect(function()
    if LogoState.active then return end
    getgenv().MizuNotify("📥 MIN", "Click = open | Right-click = close", CONFIG.THEME.Accent, 2)
    local t = TweenService:Create(Main, TweenInfo.new(.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 80, 0, 60),
        BackgroundTransparency = 1
    })
    TweenService:Create(MainStroke, TweenInfo.new(.3), { Transparency = 1 }):Play()
    t:Play()
    t.Completed:Wait()
    Main.Visible = false
    Main.Size = UDim2.new(0, 460, 0, 400)
    Main.BackgroundTransparency = .08
    createCoolLogo()
end)

BtnClose.MouseButton1Click:Connect(function()
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    cleanupLogo()
    getgenv().MizuMonitorActive = false
    getgenv().MizuNotify = nil
    Screen:Destroy()
    warn("[Mizukage] Stopped.")
end)

local whReady = WEBHOOK_URL ~= "" and WEBHOOK_URL:match("^https://discord%.com/api/webhooks/") ~= nil
local decReady = decompileFn ~= nil
getgenv().MizuNotify("✓ ONLINE v" .. CONFIG.VERSION,
    (whReady and "WH OK" or "⚠ No WH") .. " | " .. (decReady and "Decompiler OK" or "⚠ No Decompiler"),
    (whReady and decReady) and CONFIG.THEME.Success or CONFIG.THEME.Warning, 6)

warn("[Mizukage v" .. CONFIG.VERSION .. "] Loaded! Total upgrade.")