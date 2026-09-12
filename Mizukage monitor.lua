--[[ ═══════════════════════════════════════════════════════════
     ✧ Mizukage Monitor v6.0 — Live Scan Monitor ✧
     ✧ Live Progress • Partial Upload • Memory Watchdog ✧
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

-- ═══ CONFIG ═══
local CONFIG = {
    VERSION           = "6.0",
    MAX_LOGS          = 100,
    -- ═══ LOGO ═══
    LOGO_IMAGE = "rbxassetid://104266190557772",
    LOGO_FALLBACK_TEXT = "M",
    -- ═══ SCAN ═══
    SCAN_DELAY           = 0.08,
    SCAN_MAX_PER_SVC     = 200,
    SCAN_MIN_SRC_LEN     = 20,
    SCAN_MAX_SRC_CHUNK   = 2000 * 1024,    -- 2 MB per script
    SCAN_FLUSH_EVERY     = 15,
    SCAN_GC_EVERY        = 10,
    SCAN_HARD_GC_EVERY   = 30,
    SCAN_MEM_WARN_MB     = 180,
    SCAN_MEM_FLUSH_MB    = 220,
    -- ⭐ PARTIAL UPLOAD (kirim tiap 25 script)
    SCAN_PARTIAL_EVERY   = 25,
    -- ⭐ WATCHDOG (kalau stuck > 15s, warning)
    SCAN_WATCHDOG_S      = 15,
    -- ═══ DEEP SCAN ═══
    DEEP_SCAN_ENABLED    = true,
    DEEP_SCAN_MAX_TARGET = 10,
    DEEP_SCAN_PASSES     = 1,
    -- ═══ THEME ═══
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
    },
    HardIgnoreOut = { "mouse", "camera" },
    HardIgnoreIn  = {},
    SCAN_SERVICES = {
        "ReplicatedStorage", "ReplicatedFirst",
        "StarterPlayer", "StarterGui", "StarterPack",
        "ServerScriptService", "ServerStorage",
    }
}

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
    Filter = { search = "", showOut = true, showIn = true, showScan = true, showMod = true },
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
-- BUILD GUI
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

-- Notifikasi
local MAX_NOTIF = 5
local NotifHolder = Instance.new("Frame", Screen)
NotifHolder.Size = UDim2.new(0, 240, 0, 300)
NotifHolder.Position = UDim2.new(1, -250, 1, -310)
NotifHolder.BackgroundTransparency = 1
NotifHolder.ZIndex = 10
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
            frame.ZIndex = 11
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
            titleLbl.ZIndex = 12

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
            bodyLbl.ZIndex = 12

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

-- ═══════════════════════════════════════════════════════════
-- 📺 LIVE SCAN MONITOR (NEW v6.0)
-- ═══════════════════════════════════════════════════════════
local LivePanel = Instance.new("Frame", Screen)
LivePanel.Size = UDim2.new(0, 380, 0, 200)
LivePanel.Position = UDim2.new(0.5, -190, 0, 10)
LivePanel.BackgroundColor3 = Color3.fromRGB(5, 5, 10)
LivePanel.BackgroundTransparency = 0.08
LivePanel.BorderSizePixel = 0
LivePanel.Visible = false
LivePanel.ZIndex = 50
Instance.new("UICorner", LivePanel).CornerRadius = UDim.new(0, 10)
local LiveStroke = Instance.new("UIStroke", LivePanel)
LiveStroke.Color = CONFIG.THEME.Live
LiveStroke.Thickness = 2

-- Header
local LiveHeader = Instance.new("Frame", LivePanel)
LiveHeader.Size = UDim2.new(1, 0, 0, 26)
LiveHeader.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
LiveHeader.BorderSizePixel = 0
Instance.new("UICorner", LiveHeader).CornerRadius = UDim.new(0, 8)

local LiveHeaderLbl = Instance.new("TextLabel", LiveHeader)
LiveHeaderLbl.Size = UDim2.new(1, -20, 1, 0)
LiveHeaderLbl.Position = UDim2.new(0, 10, 0, 0)
LiveHeaderLbl.BackgroundTransparency = 1
LiveHeaderLbl.Text = "🔴 LIVE SCAN MONITOR v" .. CONFIG.VERSION
LiveHeaderLbl.TextColor3 = CONFIG.THEME.Live
LiveHeaderLbl.Font = Enum.Font.GothamBlack
LiveHeaderLbl.TextSize = 11
LiveHeaderLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Live progress elements
local LiveInfo = Instance.new("Frame", LivePanel)
LiveInfo.Size = UDim2.new(1, -20, 1, -36)
LiveInfo.Position = UDim2.new(0, 10, 0, 32)
LiveInfo.BackgroundTransparency = 1

local function makeLiveRow(text, yPos, color)
    local lbl = Instance.new("TextLabel", LiveInfo)
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.Position = UDim2.new(0, 0, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color or CONFIG.THEME.TextWhite
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.RichText = true
    return lbl
end

local LiveServiceLbl = makeLiveRow("Service : -", 0, CONFIG.THEME.Accent)
local LiveIndexLbl   = makeLiveRow("Index   : -", 18, CONFIG.THEME.TextMuted)
local LiveNameLbl    = makeLiveRow("Current : -", 36, CONFIG.THEME.TextWhite)
local LiveSizeLbl    = makeLiveRow("Size    : -", 54, CONFIG.THEME.Module)
local LiveMemLbl     = makeLiveRow("Memory  : -", 72, CONFIG.THEME.Success)
local LiveTimeLbl    = makeLiveRow("Elapsed : -", 90, CONFIG.THEME.TextMuted)
local LiveStatLbl    = makeLiveRow("Stats   : -", 108, CONFIG.THEME.Scan)
local LiveLastLbl    = makeLiveRow("Last 5  : -", 126, CONFIG.THEME.Live)

-- Progress bar
local LiveBarBg = Instance.new("Frame", LiveInfo)
LiveBarBg.Size = UDim2.new(1, -10, 0, 8)
LiveBarBg.Position = UDim2.new(0, 0, 1, -12)
LiveBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
LiveBarBg.BorderSizePixel = 0
Instance.new("UICorner", LiveBarBg).CornerRadius = UDim.new(0, 4)

local LiveBarFill = Instance.new("Frame", LiveBarBg)
LiveBarFill.Size = UDim2.new(0, 0, 1, 0)
LiveBarFill.BackgroundColor3 = CONFIG.THEME.Live
LiveBarFill.BorderSizePixel = 0
Instance.new("UICorner", LiveBarFill).CornerRadius = UDim.new(0, 4)

-- Watchdog label
local LiveWatchdogLbl = Instance.new("TextLabel", LivePanel)
LiveWatchdogLbl.Size = UDim2.new(1, -20, 0, 16)
LiveWatchdogLbl.Position = UDim2.new(0, 10, 1, -22)
LiveWatchdogLbl.BackgroundTransparency = 1
LiveWatchdogLbl.Text = ""
LiveWatchdogLbl.TextColor3 = CONFIG.THEME.Warning
LiveWatchdogLbl.Font = Enum.Font.GothamBold
LiveWatchdogLbl.TextSize = 10
LiveWatchdogLbl.ZIndex = 51

-- ⭐ LIVE STATE
local LiveState = {
    Service = "-",
    Index = 0,
    Total = 0,
    Name = "-",
    Size = 0,
    StartTime = 0,
    LastProgress = 0,
    LastScripts = {},  -- max 5 nama terakhir
    Success = 0,
    Fail = 0,
    Skipped = 0,
}

local function updateLiveDisplay()
    local memMB = math.floor(collectgarbage("count") / 1024)
    local elapsed = LiveState.StartTime > 0 and (os.clock() - LiveState.StartTime) or 0
    local idle = LiveState.LastProgress > 0 and (os.clock() - LiveState.LastProgress) or 0

    LiveServiceLbl.Text = string.format("Service : <b>%s</b>", LiveState.Service)
    LiveIndexLbl.Text = string.format("Index   : %d / %d", LiveState.Index, LiveState.Total)
    LiveNameLbl.Text = string.format("Current : <b>%s</b>", LiveState.Name)
    LiveSizeLbl.Text = string.format("Size    : %s", LiveState.Size > 0 and (math.floor(LiveState.Size / 1024) .. " KB") or "-")
    LiveMemLbl.Text = string.format("Memory  : %d MB %s", memMB,
        memMB > CONFIG.SCAN_MEM_WARN_MB and "⚠" or "")
    LiveTimeLbl.Text = string.format("Elapsed : %.1fs | Idle: %.1fs", elapsed, idle)
    LiveStatLbl.Text = string.format("Stats   : <b>%d✓</b> / <b>%d✗</b> / %d skip",
        LiveState.Success, LiveState.Fail, LiveState.Skipped)

    -- Last 5 scripts
    local lastStr = "-"
    if #LiveState.LastScripts > 0 then
        local parts = {}
        for i = math.max(1, #LiveState.LastScripts - 4), #LiveState.LastScripts do
            table.insert(parts, LiveState.LastScripts[i])
        end
        lastStr = table.concat(parts, " ▸ ")
    end
    LiveLastLbl.Text = "Last 5  : <i>" .. lastStr:sub(1, 60) .. "</i>"

    -- Progress bar
    if LiveState.Total > 0 then
        local pct = LiveState.Index / LiveState.Total
        LiveBarFill.Size = UDim2.new(pct, 0, 1, 0)
    else
        LiveBarFill.Size = UDim2.new(0, 0, 1, 0)
    end

    -- Watchdog
    if idle > CONFIG.SCAN_WATCHDOG_S then
        LiveWatchdogLbl.Text = string.format("⏱ STUCK %ds — script mungkin hang!", math.floor(idle))
    elseif idle > 5 then
        LiveWatchdogLbl.Text = string.format("⏳ processing %ds...", math.floor(idle))
    else
        LiveWatchdogLbl.Text = ""
    end

    -- Memory warning
    if memMB > CONFIG.SCAN_MEM_FLUSH_MB then
        LiveStroke.Color = CONFIG.THEME.Warning
    else
        LiveStroke.Color = CONFIG.THEME.Live
    end
end

local function pushLastScript(name)
    table.insert(LiveState.LastScripts, name)
    if #LiveState.LastScripts > 10 then
        table.remove(LiveState.LastScripts, 1)
    end
end

local function showLivePanel()
    LivePanel.Visible = true
    LiveState.StartTime = os.clock()
    LiveState.LastProgress = os.clock()
    LiveState.LastScripts = {}
    LiveState.Success = 0
    LiveState.Fail = 0
    LiveState.Skipped = 0
    LivePanel.Size = UDim2.new(0, 380, 0, 0)
    TweenService:Create(LivePanel, TweenInfo.new(.3, Enum.EasingStyle.Quint), {
        Size = UDim2.new(0, 380, 0, 200)
    }):Play()
end

local function hideLivePanel()
    local t = TweenService:Create(LivePanel, TweenInfo.new(.3, Enum.EasingStyle.Quint), {
        Size = UDim2.new(0, 380, 0, 0)
    })
    t:Play()
    t.Completed:Wait()
    LivePanel.Visible = false
end

-- Live update loop
task.spawn(function()
    while Screen.Parent do
        if LivePanel.Visible then
            pcall(updateLiveDisplay)
        end
        task.wait(0.15)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- MAIN WINDOW
-- ═══════════════════════════════════════════════════════════
local Main = Instance.new("Frame", Screen)
Main.Size = UDim2.new(0, 420, 0, 340)
Main.Position = UDim2.new(0.5, -210, 0.5, -170)
Main.BackgroundColor3 = CONFIG.THEME.BgBase
Main.BackgroundTransparency = .12
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
        dragging, activeInput = false, nil
    end)
end
makeDraggable(Main, Header)
makeDraggable(LivePanel, LiveHeader)

local DashBar = Instance.new("Frame", Main)
DashBar.Size = UDim2.new(1, -24, 0, 22)
DashBar.Position = UDim2.new(0, 12, 0, 40)
DashBar.BackgroundTransparency = 1
local DashLayout = Instance.new("UIListLayout", DashBar)
DashLayout.FillDirection = Enum.FillDirection.Horizontal
DashLayout.Padding = UDim.new(0, 5)

local function makeBadge(text, width)
    local f = Instance.new("Frame", DashBar)
    f.Size = UDim2.new(0, width or 80, 1, 0)
    f.BackgroundColor3 = CONFIG.THEME.CardBg
    f.BackgroundTransparency = .3
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local s = Instance.new("UIStroke", f)
    s.Color = Color3.fromRGB(40, 40, 55)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.RichText = true
    lbl.TextColor3 = CONFIG.THEME.TextMuted
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 9
    return lbl, f
end

local BadgeCalls = makeBadge("CALLS: <font color='#fff'>0</font>", 78)
local BadgeUniq  = makeBadge("UNIQ: <font color='#fff'>0</font>", 72)
local BadgeStatus = makeBadge("IDLE", 100)
local BadgeWH    = makeBadge("", 70)
if WEBHOOK_URL ~= "" and WEBHOOK_URL:match("^https://discord%.com/api/webhooks/") then
    BadgeWH.Text = "<font color='#00E1FF'>🔗 WH</font>"
else
    BadgeWH.Text = "<font color='#FF3C3C'>⚠ WH</font>"
end

local FilterBar = Instance.new("Frame", Main)
FilterBar.Size = UDim2.new(1, -24, 0, 24)
FilterBar.Position = UDim2.new(0, 12, 0, 68)
FilterBar.BackgroundColor3 = CONFIG.THEME.CardBg
FilterBar.BackgroundTransparency = .2
Instance.new("UICorner", FilterBar).CornerRadius = UDim.new(0, 4)
local fStroke = Instance.new("UIStroke", FilterBar)
fStroke.Color = Color3.fromRGB(40, 40, 55)

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
    chip.Size = UDim2.new(0, 42, 0, 18)
    chip.BackgroundColor3 = color
    chip.BackgroundTransparency = .2
    chip.Text = text
    chip.TextColor3 = CONFIG.THEME.TextWhite
    chip.Font = Enum.Font.GothamBold
    chip.TextSize = 9
    chip.AutoButtonColor = false
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 3)
    local cs = Instance.new("UIStroke", chip)
    cs.Color = color; cs.Transparency = .4
    chip.MouseButton1Click:Connect(function()
        State.Filter[keyName] = not State.Filter[keyName]
        local active = State.Filter[keyName]
        TweenService:Create(chip, TweenInfo.new(.25), {
            BackgroundTransparency = active and .2 or .85
        }):Play()
    end)
end
makeChip("OUT",  CONFIG.THEME.Out,     "showOut")
makeChip("IN",   CONFIG.THEME.Inbound, "showIn")
makeChip("SCAN", CONFIG.THEME.Scan,    "showScan")
makeChip("MOD",  CONFIG.THEME.Module,  "showMod")

local Scroll = Instance.new("ScrollingFrame", Main)
Scroll.Size = UDim2.new(1, -24, 1, -188)
Scroll.Position = UDim2.new(0, 12, 0, 100)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 3
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.ScrollBarImageColor3 = CONFIG.THEME.Accent
pcall(function() Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
local SLayout = Instance.new("UIListLayout", Scroll)
SLayout.Padding = UDim.new(0, 5)
SLayout.SortOrder = Enum.SortOrder.LayoutOrder

local BottomPanel = Instance.new("Frame", Main)
BottomPanel.Size = UDim2.new(1, -24, 0, 30)
BottomPanel.Position = UDim2.new(0, 12, 1, -38)
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
    btn.TextSize = 9
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

local BtnOut    = makeBottomBtn("OUT",    CONFIG.THEME.Out, .16)
local BtnIn     = makeBottomBtn("IN",     CONFIG.THEME.Inbound, .16)
local BtnScan   = makeBottomBtn("SCAN",   CONFIG.THEME.Scan, .18)
local BtnStop   = makeBottomBtn("STOP",   CONFIG.THEME.Warning, .16)
local BtnClear  = makeBottomBtn("CLR",    CONFIG.THEME.Clear, .16)
local BtnExport = makeBottomBtn("EXP",    CONFIG.THEME.Export, .18)

local function passFilter(entry)
    if entry.Type == "OUT"    and not State.Filter.showOut  then return false end
    if entry.Type == "IN"     and not State.Filter.showIn   then return false end
    if entry.Type == "SCAN"   and not State.Filter.showScan then return false end
    if entry.Type == "MODULE" and not State.Filter.showMod  then return false end
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
    pad.PaddingTop = UDim.new(0, 7)
    pad.PaddingBottom = UDim.new(0, 7)
    pcall(function() frame.AutomaticSize = Enum.AutomaticSize.Y end)

    local accent = Instance.new("Frame", frame)
    accent.Size = UDim2.new(0, 3, 1, -8)
    accent.Position = UDim2.new(0, 0, 0, 4)
    local acColor =
        entry.Type == "IN"     and CONFIG.THEME.Inbound or
        entry.Type == "SCAN"   and CONFIG.THEME.Scan    or
        entry.Type == "MODULE" and CONFIG.THEME.Module  or
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
        entry.Type == "MODULE" and "#FFD700" or
        "#00E1FF"

    lbl.Text = string.format(
        "<font color='#666677'>[%s]</font> <font color='%s'><b>%s</b></font> <font color='#FFFFFF'>%s</font>%s\n" ..
        "<font color='#888899'>→</font> <font color='#DCD6F7'>%s</font>\n%s",
        entry.Time, typeColor, entry.Type, entry.Name,
        entry.CallCount and entry.CallCount > 1 and (" <font color='#FFD700'>(x" .. entry.CallCount .. ")</font>") or "",
        entry.Path, entry.ArgsUI
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
        if item.Type == "SCAN" or item.Type == "MODULE" then
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

    BadgeCalls.Text = string.format("CALLS: <font color='#fff'>%d</font>", State.TotalCalls)
    BadgeUniq.Text  = string.format("UNIQ: <font color='#fff'>%d</font>", #State.Logs)
    if not State.ScanRunning then
        BadgeStatus.Text = State.RecOut and State.RecIn and "<font color='#A8E6CF'>OUT</font>+<font color='#FF8B94'>IN</font>"
            or State.RecOut and "<font color='#A8E6CF'>OUT ON</font>"
            or State.RecIn  and "<font color='#FF8B94'>IN ON</font>"
            or "IDLE"
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

-- ═══ HOOKS ═══
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
                        Time   = getPreciseTime(),
                        Type   = "OUT",
                        Obj    = self,
                        Args   = {...},
                        Method = method,
                        Caller = "Client",
                    })
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
        print("[Mizukage] __namecall hook OK")
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
                    Time   = getPreciseTime(),
                    Type   = "IN",
                    Obj    = remote,
                    Args   = {...},
                    Method = "OnClientEvent",
                    Caller = "Server",
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
                    Time   = getPreciseTime(),
                    Type   = "IN",
                    Obj    = rf,
                    Args   = {...},
                    Method = "OnClientInvoke",
                    Caller = "Server-RF",
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

-- ═══ Buttons ═══
BtnOut.MouseButton1Click:Connect(function()
    State.RecOut = not State.RecOut
    BtnOut.Text = State.RecOut and "OUT✓" or "OUT"
    BtnOut.TextColor3 = State.RecOut and CONFIG.THEME.Out or CONFIG.THEME.TextWhite
end)

BtnIn.MouseButton1Click:Connect(function()
    State.RecIn = not State.RecIn
    BtnIn.Text = State.RecIn and "IN✓" or "IN"
    BtnIn.TextColor3 = State.RecIn and CONFIG.THEME.Inbound or CONFIG.THEME.TextWhite
    getgenv().MizuNotify("IN " .. (State.RecIn and "ON" or "OFF"),
        State.RecIn and ("Hooked " .. (function() local c = 0; for _ in pairs(State.HookedRemotes) do c = c + 1 end; return c end)() .. " remotes") or "Stopped.",
        CONFIG.THEME.Inbound, 2)
end)

BtnClear.MouseButton1Click:Connect(function()
    State.Logs = {}; State.LogQueue = {}; State.RawBuffer = {}; State.TotalCalls = 0
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    pcall(function() collectgarbage("collect") end)
end)

BtnStop.MouseButton1Click:Connect(function()
    if State.ScanRunning then
        State.ScanAbort = true
        getgenv().MizuNotify("⏹ STOP", "Scan dibatalkan...", CONFIG.THEME.Warning, 3)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- 🚀 SCAN v6.0 — LIVE MONITOR + PARTIAL UPLOAD
-- ═══════════════════════════════════════════════════════════
BtnScan.MouseButton1Click:Connect(function()
    if State.ScanRunning then
        getgenv().MizuNotify("⚠ SIBUK", "Scan sedang berjalan.", CONFIG.THEME.Warning, 3)
        return
    end
    if not decompileFn then
        getgenv().MizuNotify("SCAN GAGAL", "Executor tidak support 'decompile'.", CONFIG.THEME.Warning, 5)
        return
    end

    State.ScanRunning = true
    State.ScanAbort = false
    BadgeStatus.Text = "<font color='#B450FF'>SCAN...</font>"
    showLivePanel()
    getgenv().MizuNotify("🚀 SCAN v6.0 START",
        "Live monitor aktif di atas layar",
        CONFIG.THEME.Live, 4)

    -- ⭐ Start watchdog loop
    getgenv().MizuWatchdog = true
    task.spawn(function()
        while getgenv().MizuWatchdog do
            if LiveState.LastProgress > 0 then
                local idle = os.clock() - LiveState.LastProgress
                if idle > CONFIG.SCAN_WATCHDOG_S then
                    LiveWatchdogLbl.Text = string.format("⏱ STUCK %ds — script %s", math.floor(idle), LiveState.Name)
                end
            end
            task.wait(1)
        end
    end)

    task.spawn(function()
        local totalScripts = 0
        local successCount = 0
        local failCount = 0
        local skippedCount = 0
        local startClock = os.clock()

        State.LastDump = {}
        local scanned = {}

        -- ═══ PASS 1: Per service ═══
        for _, serviceName in ipairs(CONFIG.SCAN_SERVICES) do
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

                    -- ⭐ UPDATE LIVE STATE sebelum decompile
                    LiveState.Index = i
                    LiveState.Name = obj.Name
                    LiveState.Size = 0
                    LiveState.LastProgress = os.clock()
                    pushLastScript(obj.Name)

                    local ok, err = pcall(function()
                        local sType = getScriptType(obj)
                        local path = getInstancePath(obj)

                        -- Decompile
                        local decompOk, result = pcall(decompileFn, obj)
                        local source = (decompOk and type(result) == "string") and result or ""

                        LiveState.Size = #source

                        -- Cek terlalu besar
                        if #source > CONFIG.SCAN_MAX_SRC_CHUNK then
                            skippedCount = skippedCount + 1
                            LiveState.Skipped = skippedCount
                            svcChunks[#svcChunks + 1] = string.format(
                                "\n-- [TOO BIG] %s — %s\n-- Path: %s\n-- Size: %d KB (limit %d KB)\n\n",
                                sType, obj.Name, path,
                                math.floor(#source / 1024),
                                math.floor(CONFIG.SCAN_MAX_SRC_CHUNK / 1024))
                            totalScripts = totalScripts + 1
                            source = nil
                            result = nil
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
                                sType, obj.Name, path
                            )
                        end

                        totalScripts = totalScripts + 1
                        source = nil
                        result = nil
                    end)

                    if not ok then
                        failCount = failCount + 1
                        LiveState.Fail = failCount
                        totalScripts = totalScripts + 1
                    end

                    -- Flush buffer
                    if i % CONFIG.SCAN_FLUSH_EVERY == 0 and #svcChunks > 0 then
                        local combined = table.concat(svcChunks, "")
                        svcChunks = { combined }
                        combined = nil
                        pcall(function() collectgarbage("step") end)
                    end

                    -- ⭐ PARTIAL UPLOAD setiap 25 script
                    if i % CONFIG.SCAN_PARTIAL_EVERY == 0 and #svcChunks > 0 then
                        pcall(function()
                            local partialContent = table.concat(svcChunks, "")
                            local partialName = string.format("%s_%s_partial.lua",
                                safeFileName(GameName), safeFileName(LocalPlayer.Name))
                            local boundary = "----Partial" .. tostring(math.random(100000, 999999))
                            local jsonBody = HttpService:JSONEncode({
                                username = "Mizukage Live",
                                content = "📊 **Partial scan** — " .. serviceName
                                    .. " — " .. i .. "/" .. #allScripts
                                    .. " — " .. successCount .. "✓ " .. failCount .. "✗",
                            })
                            local body = "--" .. boundary .. "\r\n"
                                .. 'Content-Disposition: form-data; name="payload_json"\r\n'
                                .. "Content-Type: application/json\r\n\r\n"
                                .. jsonBody .. "\r\n"
                                .. "--" .. boundary .. "\r\n"
                                .. 'Content-Disposition: form-data; name="file"; filename="' .. partialName .. '"\r\n'
                                .. "Content-Type: text/plain\r\n\r\n"
                                .. partialContent .. "\r\n"
                                .. "--" .. boundary .. "--\r\n"
                            httpRequest({
                                Url = WEBHOOK_URL, Method = "POST",
                                Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                                Body = body,
                            })
                        end)
                    end

                    -- Update badge
                    if i % 3 == 0 or i == #allScripts then
                        BadgeStatus.Text = string.format(
                            "<font color='#B450FF'>%d✓/%d✗</font>",
                            successCount, failCount + skippedCount)
                    end

                    task.wait(CONFIG.SCAN_DELAY)

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

        -- ═══ DEEP SCAN ═══
        if CONFIG.DEEP_SCAN_ENABLED and not State.ScanAbort then
            LiveState.Service = "_DEEP_SCAN"
            LiveState.Name = "building pool..."
            LiveState.LastProgress = os.clock()

            local pool = {}
            local pathIndex = {}
            for _, svcName in ipairs(CONFIG.SCAN_SERVICES) do
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

            LiveState.Name = "extracting refs..."

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

            LiveState.Name = "matching targets..."

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
            refs = nil
            pool = nil
            pathIndex = nil
            pcall(function() collectgarbage("collect") end)

            if #newTargets > 0 then
                LiveState.Total = #newTargets
                LiveState.Index = 0

                local deepChunks = { "\n-- ═══ DEEP SCAN (REFERENCE) ═══\n" }
                for i = 1, #newTargets do
                    if State.ScanAbort then break end
                    local obj = newTargets[i]

                    LiveState.Index = i
                    LiveState.Name = obj.Name
                    LiveState.LastProgress = os.clock()
                    pushLastScript(obj.Name)

                    pcall(function()
                        local sType = getScriptType(obj)
                        local path = getInstancePath(obj)
                        local decompOk, result = pcall(decompileFn, obj)
                        local source = (decompOk and type(result) == "string") and result or ""

                        LiveState.Size = #source

                        if #source > 500 * 1024 then
                            deepChunks[#deepChunks + 1] = "-- [TOO BIG] " .. sType .. " — " .. obj.Name
                                .. " (" .. math.floor(#source / 1024) .. " KB)\n"
                            return
                        end

                        if source ~= "" and not source:find("failed to decompile") then
                            successCount = successCount + 1
                            LiveState.Success = successCount
                            deepChunks[#deepChunks + 1] = string.format(
                                "\n-- [DEEP] %s — %s\n-- Path: %s\n-- ═══\n%s\n",
                                sType, obj.Name, path, source
                            )
                        end
                        totalScripts = totalScripts + 1
                    end)

                    task.wait(CONFIG.SCAN_DELAY)
                end

                State.LastDump["_DEEP_SCAN"] = table.concat(deepChunks, "")
                deepChunks = nil
                newTargets = nil
                pcall(function() collectgarbage("collect") end)
            end
        end

        -- ═══ SELESAI ═══
        local elapsed = os.clock() - startClock
        BadgeStatus.Text = string.format(
            "<font color='#A8E6CF'>%d✓</font>/<font color='#FF8080'>%d✗</font>",
            successCount, failCount + skippedCount)

        getgenv().MizuWatchdog = false

        if State.ScanAbort then
            getgenv().MizuNotify("⏹ DIHENTIKAN",
                string.format("%d scripts • %.1fs", totalScripts, elapsed),
                CONFIG.THEME.Warning, 5)
        else
            getgenv().MizuNotify("🎉 SCAN SELESAI",
                string.format("%d scripts • %d✓ %d✗ %d skip • %.1fs",
                    totalScripts, successCount, failCount, skippedCount, elapsed),
                CONFIG.THEME.Success, 6)
        end

        task.wait(2)
        hideLivePanel()

        State.ScanRunning = false
        State.ScanAbort = false
        pcall(function() collectgarbage("collect") end)
    end)
end)

-- ═══════════════════════════════════════════════════════════
-- 📤 EXPORT
-- ═══════════════════════════════════════════════════════════
BtnExport.MouseButton1Click:Connect(function()
    if WEBHOOK_URL == "" or not WEBHOOK_URL:match("^https://discord%.com/api/webhooks/") then
        getgenv().MizuNotify("EXP GAGAL", "Webhook kosong.", CONFIG.THEME.Warning, 4)
        return
    end
    if not httpRequest then
        getgenv().MizuNotify("EXP GAGAL", "Executor tidak support HTTP.", CONFIG.THEME.Warning, 4)
        return
    end

    local hasScan = next(State.LastDump) ~= nil
    local hasLogs = #State.Logs > 0

    if not hasScan and not hasLogs then
        getgenv().MizuNotify("EXP GAGAL", "Belum ada data. Scan dulu.", CONFIG.THEME.Warning, 4)
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
        table.insert(lines, "║     MIZUKAGE MONITOR v6.0 — PACKED DUMP                  ║")
        table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
        table.insert(lines, "")
        table.insert(lines, "-- ═══ METADATA ═══")
        table.insert(lines, "-- Game Name    : " .. GameName)
        table.insert(lines, "-- Place ID     : " .. placeId)
        table.insert(lines, "-- Job ID       : " .. jobId)
        table.insert(lines, "-- Player       : " .. playerName .. " (" .. displayName .. ")")
        table.insert(lines, "-- User ID      : " .. tostring(userId))
        table.insert(lines, "-- Export Time  : " .. os.date("%Y-%m-%d %H:%M:%S"))
        table.insert(lines, "-- Executor     : Mizukage v" .. CONFIG.VERSION)
        table.insert(lines, "")

        if hasScan then
            local totalFiles, totalBytes = 0, 0
            for _, content in pairs(State.LastDump) do
                totalFiles = totalFiles + 1
                totalBytes = totalBytes + #content
            end
            table.insert(lines, "-- Total Sections : " .. totalFiles)
            table.insert(lines, "-- Total Size     : " .. string.format("%.1f KB", totalBytes / 1024))
            table.insert(lines, "")

            for _, svcName in ipairs(CONFIG.SCAN_SERVICES) do
                local content = State.LastDump[svcName]
                if content then
                    table.insert(lines, "")
                    table.insert(lines, "╔══════════════════════════════════════════════════════════╗")
                    table.insert(lines, "║  📂 SERVICE: " .. string.format("%-43s", svcName) .. "║")
                    table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
                    table.insert(lines, "")
                    table.insert(lines, content)
                    table.insert(lines, "")
                    table.insert(lines, "-- ═══ END OF " .. svcName .. " ═══")
                    table.insert(lines, "")
                end
            end

            if State.LastDump["_DEEP_SCAN"] then
                table.insert(lines, "")
                table.insert(lines, "╔══════════════════════════════════════════════════════════╗")
                table.insert(lines, "║  🔍 DEEP SCAN RESULTS                                    ║")
                table.insert(lines, "╚══════════════════════════════════════════════════════════╝")
                table.insert(lines, "")
                table.insert(lines, State.LastDump["_DEEP_SCAN"])
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
                table.insert(lines, string.format("-- [%s | %s] %s | Method: %s | Calls: %d",
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
            description = "**Scan dump** dari game **" .. GameName .. "**\n"
                .. "Target: `" .. playerName .. "` (`" .. tostring(userId) .. "`)\n"
                .. "Mizukage Monitor v" .. CONFIG.VERSION,
            color = 0x00E1FF,
            timestamp = timestamp,
            footer = { text = "Mizukage v" .. CONFIG.VERSION .. " • " .. placeId },
            fields = {
                { name = "🎮 Game", value = "`" .. GameName .. "`", inline = true },
                { name = "🆔 Place ID", value = "`" .. placeId .. "`", inline = true },
                { name = "👤 Player", value = "`" .. playerName .. "`", inline = true },
                { name = "📦 File", value = "`" .. fileName .. "`", inline = false },
                { name = "📊 Size", value = string.format("%.1f KB", packedSize / 1024), inline = true },
                { name = "🗂️ Sections", value = tostring((function() local c = 0; for _ in pairs(State.LastDump) do c = c + 1 end; return c end)()), inline = true },
                { name = "📡 Logs", value = tostring(#State.Logs), inline = true },
            },
        }
        if avatarUrl then embed.thumbnail = { url = avatarUrl } end

        local boundary = "----MizuBoundary" .. tostring(math.random(100000, 999999))
        local jsonBody = HttpService:JSONEncode({
            username   = profileName,
            avatar_url = profileAvatar,
            embeds     = { embed },
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

        getgenv().MizuNotify("📤 UPLOAD",
            string.format("%s (%.1f KB)", fileName, packedSize / 1024), CONFIG.THEME.Export, 4)

        local success, err = false, nil
        for attempt = 1, 3 do
            local ok, res = pcall(function()
                return httpRequest({
                    Url = WEBHOOK_URL, Method = "POST",
                    Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
                    Body = body,
                })
            end)
            if ok and res and res.Success then success = true; break
            else
                err = ok and ("HTTP " .. tostring(res and res.StatusCode or "?")) or res
                if attempt < 3 then task.wait(2 + attempt) end
            end
        end

        body = nil
        pcall(function() collectgarbage("collect") end)

        if success then
            getgenv().MizuNotify("✅ EXPORT SUKSES", "File: " .. fileName, CONFIG.THEME.Success, 6)
        else
            getgenv().MizuNotify("❌ EXPORT GAGAL", tostring(err):sub(1, 60), CONFIG.THEME.Warning, 5)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════
-- 🎨 COOL LOGO SYSTEM
-- ═══════════════════════════════════════════════════════════

local LogoState = {
    active = false,
    logoObj = nil,
    pulseConn = nil,
    ringAngle = 0,
    ringConn = nil,
}

local function createCoolLogo()
    if LogoState.logoObj then pcall(function() LogoState.logoObj:Destroy() end) end
    if LogoState.pulseConn then pcall(function() LogoState.pulseConn:Disconnect() end) end
    if LogoState.ringConn then pcall(function() LogoState.ringConn:Disconnect() end) end

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
    RingStroke.Transparency = 0
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

    local Tooltip = Instance.new("Frame", LogoRoot)
    Tooltip.Size = UDim2.new(0, 110, 0, 24)
    Tooltip.Position = UDim2.new(1, 10, 0.5, -12)
    Tooltip.BackgroundColor3 = CONFIG.THEME.CardBg
    Tooltip.BackgroundTransparency = .05
    Tooltip.BorderSizePixel = 0
    Tooltip.ZIndex = 25
    Tooltip.Visible = false
    Instance.new("UICorner", Tooltip).CornerRadius = UDim.new(0, 6)
    local TS = Instance.new("UIStroke", Tooltip); TS.Color = CONFIG.THEME.Accent; TS.Transparency = .3

    local TooltipLabel = Instance.new("TextLabel", Tooltip)
    TooltipLabel.Size = UDim2.new(1, 0, 1, 0)
    TooltipLabel.BackgroundTransparency = 1
    TooltipLabel.Text = "CLICK TO OPEN"
    TooltipLabel.TextColor3 = CONFIG.THEME.TextWhite
    TooltipLabel.Font = Enum.Font.GothamBold
    TooltipLabel.TextSize = 10
    TooltipLabel.ZIndex = 26

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

    LogoBody.MouseEnter:Connect(function()
        TweenService:Create(LogoRoot, TweenInfo.new(.25, Enum.EasingStyle.Quint), {
            Size = UDim2.new(0, 66, 0, 66)
        }):Play()
        TweenService:Create(Glow, TweenInfo.new(.25), {BackgroundTransparency = 0.4}):Play()
        TweenService:Create(BodyStroke, TweenInfo.new(.25), {Transparency = 0.05, Thickness = 2}):Play()
        Tooltip.Visible = true
        TweenService:Create(Tooltip, TweenInfo.new(.2, Enum.EasingStyle.Quint), {
            Position = UDim2.new(1, 6, 0.5, -12)
        }):Play()
    end)

    LogoBody.MouseLeave:Connect(function()
        TweenService:Create(LogoRoot, TweenInfo.new(.3, Enum.EasingStyle.Quint), {
            Size = UDim2.new(0, 58, 0, 58)
        }):Play()
        TweenService:Create(BodyStroke, TweenInfo.new(.3), {Thickness = 1.5}):Play()
        TweenService:Create(Tooltip, TweenInfo.new(.2, Enum.EasingStyle.Quint), {
            Position = UDim2.new(1, 10, 0.5, -12)
        }):Play()
        task.delay(0.2, function()
            if Tooltip and Tooltip.Parent then Tooltip.Visible = false end
        end)
    end)

    LogoBody.MouseButton1Click:Connect(function()
        TweenService:Create(LogoRoot, TweenInfo.new(.2, Enum.EasingStyle.Back), {
            Size = UDim2.new(0, 30, 0, 30)
        }):Play()
        TweenService:Create(Glow, TweenInfo.new(.2), {BackgroundTransparency = 0.1}):Play()

        task.wait(0.18)

        Main.Visible = true
        Main.Size = UDim2.new(0, 100, 0, 80)
        Main.BackgroundTransparency = 1
        MainStroke.Transparency = 1

        TweenService:Create(Main, TweenInfo.new(.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 420, 0, 340),
            BackgroundTransparency = .12
        }):Play()
        TweenService:Create(MainStroke, TweenInfo.new(.4), {Transparency = 0}):Play()

        task.wait(0.4)
        if LogoState.pulseConn then pcall(function() LogoState.pulseConn:Disconnect() end) end
        if LogoState.ringConn then pcall(function() LogoState.ringConn:Disconnect() end) end
        LogoState.active = false
        LogoState.logoObj = nil
        pcall(function() LogoRoot:Destroy() end)
    end)

    LogoBody.MouseButton2Click:Connect(function()
        TweenService:Create(Glow, TweenInfo.new(.15), {
            BackgroundColor3 = CONFIG.THEME.Warning,
            BackgroundTransparency = 0.1
        }):Play()
        TweenService:Create(BodyStroke, TweenInfo.new(.15), {
            Color = CONFIG.THEME.Warning,
            Transparency = 0
        }):Play()

        task.wait(0.25)
        getgenv().MizuNotify("🔌 CLOSING", "Mematikan...", CONFIG.THEME.Warning, 2)
        task.wait(0.3)

        State.ScanAbort = true
        getgenv().MizuWatchdog = false
        for _, c in ipairs(State.Connections) do
            pcall(function() c:Disconnect() end)
        end
        getgenv().MizuMonitorActive = false
        getgenv().MizuNotify = nil
        Screen:Destroy()
        warn("[Mizukage] Stopped & cleaned.")
    end)

    LogoRoot.Size = UDim2.new(0, 0, 0, 0)
    TweenService:Create(LogoRoot, TweenInfo.new(.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 58, 0, 58)
    }):Play()
end

BtnMin.MouseButton1Click:Connect(function()
    if LogoState.active then return end
    getgenv().MizuNotify("📥 MINIMIZED", "Click = open • Right-click = close", CONFIG.THEME.Accent, 3)

    local minTween = TweenService:Create(Main, TweenInfo.new(.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 80, 0, 60),
        BackgroundTransparency = 1
    })
    TweenService:Create(MainStroke, TweenInfo.new(.3), {Transparency = 1}):Play()
    minTween:Play()
    minTween.Completed:Wait()

    Main.Visible = false
    Main.Size = UDim2.new(0, 420, 0, 340)
    Main.BackgroundTransparency = .12
    createCoolLogo()
end)

BtnClose.MouseButton1Click:Connect(function()
    local originalPos = Main.Position
    local shakeOffsets = {
        UDim2.new(originalPos.X.Scale, originalPos.X.Offset - 8, originalPos.Y.Scale, originalPos.Y.Offset),
        UDim2.new(originalPos.X.Scale, originalPos.X.Offset + 8, originalPos.Y.Scale, originalPos.Y.Offset),
        UDim2.new(originalPos.X.Scale, originalPos.X.Offset - 5, originalPos.Y.Scale, originalPos.Y.Offset),
        UDim2.new(originalPos.X.Scale, originalPos.X.Offset + 5, originalPos.Y.Scale, originalPos.Y.Offset),
        originalPos,
    }
    for _, pos in ipairs(shakeOffsets) do
        TweenService:Create(Main, TweenInfo.new(.05), {Position = pos}):Play()
        task.wait(0.05)
    end

    TweenService:Create(MainStroke, TweenInfo.new(.2), {Color = CONFIG.THEME.Warning}):Play()
    task.wait(0.1)
    getgenv().MizuNotify("🔌 SHUTDOWN", "Cleaning up...", CONFIG.THEME.Warning, 3)
    task.wait(0.3)

    TweenService:Create(Main, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 30, 0, 30),
        BackgroundTransparency = 1
    }):Play()
    TweenService:Create(MainStroke, TweenInfo.new(.3), {Transparency = 1}):Play()

    task.wait(0.3)

    State.ScanAbort = true
    getgenv().MizuWatchdog = false
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    getgenv().MizuMonitorActive = false
    getgenv().MizuNotify = nil
    Screen:Destroy()
    warn("[Mizukage] Stopped & cleaned.")
end)

local whReady = WEBHOOK_URL ~= "" and WEBHOOK_URL:match("^https://discord%.com/api/webhooks/") ~= nil
local decReady = decompileFn ~= nil
getgenv().MizuNotify("✓ ONLINE v" .. CONFIG.VERSION,
    (whReady and "WH OK" or "⚠ No WH") .. " | " .. (decReady and "Decompiler OK" or "⚠ No Decompiler"),
    (whReady and decReady) and CONFIG.THEME.Success or CONFIG.THEME.Warning, 6)

warn("[Mizukage v" .. CONFIG.VERSION .. "] Loaded! Live scanner monitor active.")