--[[
    Fe UGC Animations Studio v4.0  —  полный рекод
    • Новый UI: боковое меню, список, панель предпросмотра
    • Wear by ID, Set Builder, Sets, Favorites, Current
    • Один файл сохранения (fua40_data.json), кэш ID анимаций на диске
    • RightShift — скрыть / показать окно
]]

local Players       = game:GetService("Players")
local AssetService  = game:GetService("AssetService")
local AvatarEditor  = game:GetService("AvatarEditorService")
local RunService    = game:GetService("RunService")
local HttpService   = game:GetService("HttpService")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local LP            = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════
--  THEME
-- ═══════════════════════════════════════════════════════════════════════
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local T = {
    bg = rgb(11, 13, 21), panel = rgb(17, 20, 32), panel2 = rgb(24, 28, 44), panel3 = rgb(33, 38, 60),
    line = rgb(40, 46, 74), text = rgb(236, 241, 255), sub = rgb(146, 158, 196), dim = rgb(86, 98, 134),
    accent = rgb(108, 140, 255), accent2 = rgb(172, 100, 255), good = rgb(66, 214, 140),
    bad = rgb(255, 88, 104), warn = rgb(255, 160, 56), gold = rgb(255, 207, 70), cyan = rgb(58, 208, 240),
    white = Color3.new(1, 1, 1),
}

local SLOTS = {
    { key = "idleanimation",     folder = "idle",     label = "Idle",   icon = "🧍", color = rgb(104, 178, 255) },
    { key = "walkanimation",     folder = "walk",     label = "Walk",   icon = "🚶", color = rgb(80, 228, 150) },
    { key = "runanimation",      folder = "run",      label = "Run",    icon = "🏃", color = rgb(255, 150, 60) },
    { key = "jumpanimation",     folder = "jump",     label = "Jump",   icon = "⬆",  color = rgb(210, 96, 255) },
    { key = "fallanimation",     folder = "fall",     label = "Fall",   icon = "⬇",  color = rgb(255, 84, 104) },
    { key = "climbanimation",    folder = "climb",    label = "Climb",  icon = "🧗", color = rgb(80, 220, 255) },
    { key = "swimidleanimation", folder = "swimidle", label = "S.Idle", icon = "🏊", color = rgb(255, 214, 72) },
    { key = "swimanimation",     folder = "swim",     label = "Swim",   icon = "🌊", color = rgb(255, 110, 190) },
}
local SLOT = {}
for _, s in ipairs(SLOTS) do SLOT[s.key] = s end

local PROP = {
    idle = "IdleAnimation", walk = "WalkAnimation", run = "RunAnimation", jump = "JumpAnimation",
    fall = "FallAnimation", climb = "ClimbAnimation", swim = "SwimAnimation", swimidle = "SwimAnimation",
}

local NAV = {
    { id = "Browse",    icon = "🔎", label = "Browse",    title = "Browse bundles",  sub = "Search the catalog, preview and wear", color = T.accent },
    { id = "Favorites", icon = "⭐", label = "Favorites", title = "Favorites",       sub = "Your saved bundles",                   color = T.gold },
    { id = "Builder",   icon = "🛠", label = "Builder",   title = "Set Builder",     sub = "Mix slots from different bundles",     color = T.warn },
    { id = "Sets",      icon = "💾", label = "My Sets",   title = "My Sets",         sub = "Saved combinations",                   color = T.accent2 },
    { id = "Current",   icon = "✅", label = "Current",   title = "Equipped now",    sub = "What your character is wearing",       color = T.good },
    { id = "ById",      icon = "🎯", label = "By ID",     title = "Wear by ID",      sub = "Apply any animation asset ID",         color = T.cyan },
}

-- ═══════════════════════════════════════════════════════════════════════
--  STORAGE (один файл, сохранение с задержкой)
-- ═══════════════════════════════════════════════════════════════════════
local FILE = "fua40_data.json"
local CAN_FS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"

local DB = {
    cache = {}, equipped = {}, presets = {}, favs = {}, history = {}, builder = {},
    ui = { tab = "Browse", slot = "idleanimation", bundleId = nil, bundleName = "" },
}
if CAN_FS and isfile(FILE) then
    local ok, raw = pcall(readfile, FILE)
    if ok and raw and raw ~= "" then
        local ok2, t = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(t) == "table" then
            for k, v in pairs(t) do if type(v) == "table" then DB[k] = v end end
        end
    end
end

local saveQueued = false
local function save()
    if not CAN_FS or saveQueued then return end
    saveQueued = true
    task.delay(0.4, function()
        saveQueued = false
        pcall(function() writefile(FILE, HttpService:JSONEncode(DB)) end)
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════════
local S = {
    tab = "Browse", slot = SLOT[DB.ui.slot] and DB.ui.slot or "idleanimation",
    results = {}, pages = nil, page = 1, perPage = 10, searchId = 0, loading = false,
    bundleId = DB.ui.bundleId, bundleName = DB.ui.bundleName or "", items = {}, bundleCache = {},
    defaults = {}, gen = 0, track = nil, wm = nil, cam = nil, vpConn = nil,
    idText = "", slotHint = nil, cardRefs = {},
}
for _, n in ipairs(NAV) do if n.id == DB.ui.tab then S.tab = n.id end end

local conns = {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end

-- ═══════════════════════════════════════════════════════════════════════
--  UI HELPERS
-- ═══════════════════════════════════════════════════════════════════════
local function new(class, props, kids)
    local o = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else o[k] = v end
    end
    for _, k in ipairs(kids or {}) do k.Parent = o end
    if parent then o.Parent = parent end
    return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(col, th, tr)
    return new("UIStroke", { Color = col or T.line, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function pad(l, t, r, b)
    return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0), PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0) })
end
local function gradient(c0, c1, rot)
    return new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rot or 0 })
end
local function tween(o, t, props)
    local tw = TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play(); return tw
end
local function trunc(s, n)
    s = tostring(s or "?")
    local l = utf8.len(s)
    if l and l > n then return s:sub(1, (utf8.offset(s, n) or n + 1) - 1) .. "…" end
    return s
end
local function timeAgo(t)
    if not t then return "" end
    local d = os.time() - t
    if d < 60 then return "just now" elseif d < 3600 then return math.floor(d / 60) .. "m ago"
    elseif d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

local function label(parent, text, size, color, pos, sz, font)
    return new("TextLabel", {
        Parent = parent, BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color or T.text,
        Font = font or Enum.Font.GothamMedium, Position = pos or UDim2.new(), Size = sz or UDim2.new(1, 0, 0, size + 4),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local function button(parent, text, col, size, pos, ts)
    local b = new("TextButton", {
        Parent = parent, Size = size, Position = pos or UDim2.new(), BackgroundColor3 = col, Text = text,
        TextColor3 = T.white, Font = Enum.Font.GothamBold, TextSize = ts or 12, AutoButtonColor = false,
        BorderSizePixel = 0, TextTruncate = Enum.TextTruncate.AtEnd,
    }, { corner(8) })
    b:SetAttribute("col", col); b:SetAttribute("base", col); b:SetAttribute("on", true)
    b.MouseEnter:Connect(function()
        if b:GetAttribute("on") then tween(b, 0.1, { BackgroundColor3 = b:GetAttribute("base"):Lerp(T.white, 0.14) }) end
    end)
    b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = b:GetAttribute("base") }) end)
    return b
end
local function setEnabled(b, on)
    b:SetAttribute("on", on)
    local base = on and b:GetAttribute("col") or T.panel3
    b:SetAttribute("base", base); b.BackgroundColor3 = base
    b.TextTransparency = on and 0 or 0.55
end
local function click(b, fn)
    b.MouseButton1Click:Connect(function() if b:GetAttribute("on") ~= false then fn() end end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  ANIMATION ENGINE
-- ═══════════════════════════════════════════════════════════════════════
local function extract(animate, folderName, wantIdle)
    local f = animate:FindFirstChild(folderName)
    if not f then return nil end
    for _, c in ipairs(f:GetChildren()) do
        if c:IsA("Animation") and c.AnimationId ~= "" then
            if not wantIdle or c.Name:lower():find("idle") then
                return { Name = c.Name, AnimationId = c.AnimationId }
            end
        end
    end
end

-- Получаем AnimationId из бандл-ассета (через HumanoidDescription), результат кэшируется на диск
local function fetchAnim(item, slotKey)
    local s = SLOT[slotKey]; if not s then return nil end
    local ck = tostring(item.Id) .. "_" .. slotKey
    if DB.cache[ck] then return DB.cache[ck] end
    local result
    pcall(function()
        local desc = Instance.new("HumanoidDescription")
        desc[PROP[s.folder]] = tonumber(item.Id)
        local dummy = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        local animate = dummy:FindFirstChild("Animate")
        if animate then
            if slotKey == "swimidleanimation" then
                result = extract(animate, "swimidle", false) or extract(animate, "swim", true)
            else
                result = extract(animate, s.folder, false)
            end
        end
        dummy:Destroy()
    end)
    if not result then
        pcall(function()
            local objs = game:GetObjects("rbxassetid://" .. tostring(item.Id))
            local function find(inst)
                if result then return end
                if inst:IsA("Animation") and inst.AnimationId ~= "" then
                    result = { Name = inst.Name, AnimationId = inst.AnimationId }; return
                end
                for _, c in ipairs(inst:GetChildren()) do find(c) end
            end
            if objs and objs[1] then find(objs[1]) end
        end)
    end
    if result then DB.cache[ck] = result; save() end
    return result
end

local function stopTracks(hum)
    for _, t in ipairs(hum:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end
end

local function setSlotAnim(char, slotKey, data)
    local animate = char and char:FindFirstChild("Animate")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local s = SLOT[slotKey]
    if not animate or not hum or not s then return false end
    local folder = animate:FindFirstChild(s.folder)
    if not folder then return false end
    animate.Disabled = true
    stopTracks(hum)
    for _, c in ipairs(folder:GetChildren()) do if c:IsA("Animation") then c:Destroy() end end
    new("Animation", { Name = "Animation1", AnimationId = data.AnimationId, Parent = folder })
    task.wait(0.05)
    animate.Disabled = false
    return true
end

local function applySlot(slotKey, data)
    if setSlotAnim(LP.Character, slotKey, data) then
        DB.equipped[slotKey] = { Name = data.Name, AnimationId = data.AnimationId }
        save(); return true
    end
    return false
end

local function resetSlot(slotKey)
    local char = LP.Character
    local animate = char and char:FindFirstChild("Animate")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local s = SLOT[slotKey]
    DB.equipped[slotKey] = nil; save()
    if not animate or not hum or not s then return end
    local folder = animate:FindFirstChild(s.folder); if not folder then return end
    animate.Disabled = true
    stopTracks(hum)
    for _, c in ipairs(folder:GetChildren()) do if c:IsA("Animation") then c:Destroy() end end
    for _, d in ipairs(S.defaults[slotKey] or {}) do d:Clone().Parent = folder end
    task.wait(0.05)
    animate.Disabled = false
end

local function captureDefaults(animate)
    for _, s in ipairs(SLOTS) do
        local f = animate:FindFirstChild(s.folder)
        S.defaults[s.key] = {}
        if f then
            for _, c in ipairs(f:GetChildren()) do
                if c:IsA("Animation") then table.insert(S.defaults[s.key], c:Clone()) end
            end
        end
    end
end

local function countEquipped() local n = 0; for _ in pairs(DB.equipped) do n += 1 end; return n end

-- ═══════════════════════════════════════════════════════════════════════
--  SCREEN + WINDOW
-- ═══════════════════════════════════════════════════════════════════════
local function getParent()
    if typeof(gethui) == "function" then
        local ok, h = pcall(gethui); if ok and h then return h end
    end
    local cg = game:GetService("CoreGui")
    if pcall(function() return cg:GetChildren() end) then return cg end
    return LP:WaitForChild("PlayerGui")
end
local PARENT = getParent()
for _, n in ipairs({ "FUA_Studio", "FUA37" }) do
    local old = PARENT:FindFirstChild(n); if old then old:Destroy() end
end

local Screen = new("ScreenGui", {
    Name = "FUA_Studio", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
})
Screen.Parent = PARENT

local WIN_W, WIN_H = 880, 540
local Win = new("Frame", {
    Parent = Screen, Name = "Win", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundColor3 = T.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, { corner(16), stroke(T.line, 1.5, 0.1) })
gradient(rgb(14, 17, 30), rgb(9, 11, 18), 135).Parent = Win
local UIScaleObj = new("UIScale", { Parent = Win })
local function calcScale()
    local v = Screen.AbsoluteSize
    return math.clamp(math.min(v.X / 960, v.Y / 620), 0.5, 1.4)
end
UIScaleObj.Scale = calcScale()
bind(Screen:GetPropertyChangedSignal("AbsoluteSize"), function() UIScaleObj.Scale = calcScale() end)

-- Top bar
local TopBar = new("Frame", { Parent = Win, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = T.panel, BorderSizePixel = 0 })
local topLine = new("Frame", { Parent = TopBar, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = T.accent, BorderSizePixel = 0 })
gradient(T.accent, T.accent2, 0).Parent = topLine
local Logo = new("Frame", { Parent = TopBar, Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(14, 9), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, { corner(8) })
gradient(T.accent, T.accent2, 45).Parent = Logo
new("TextLabel", { Parent = Logo, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "▶", TextColor3 = T.white, Font = Enum.Font.GothamBlack, TextSize = 13 })
label(TopBar, "UGC Animations Studio", 15, T.text, UDim2.fromOffset(52, 6), UDim2.new(0, 300, 0, 20), Enum.Font.GothamBlack)
label(TopBar, "v4.0  •  RightShift to hide", 10, T.dim, UDim2.fromOffset(52, 26), UDim2.new(0, 300, 0, 14), Enum.Font.Gotham)

local BtnMin = button(TopBar, "—", T.panel3, UDim2.fromOffset(28, 28), UDim2.new(1, -74, 0, 9), 14)
local BtnClose = button(TopBar, "✕", rgb(176, 46, 58), UDim2.fromOffset(28, 28), UDim2.new(1, -40, 0, 9), 13)

local Pill = new("TextButton", {
    Parent = Screen, Size = UDim2.fromOffset(88, 32), Position = UDim2.new(0, 14, 1, -48), BackgroundColor3 = T.panel,
    Text = "▶  UGC", TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, Visible = false,
}, { corner(10), stroke(T.accent, 1.5, 0.2) })
local function setVisible(v) Win.Visible = v; Pill.Visible = not v end
BtnMin.MouseButton1Click:Connect(function() setVisible(false) end)
Pill.MouseButton1Click:Connect(function() setVisible(true) end)
bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then setVisible(not Win.Visible) end
end)

-- Drag (мышь + тач)
do
    local dragging, startIn, startCenter = false, nil, nil
    local function isPointer(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
    bind(TopBar.InputBegan, function(i)
        if isPointer(i) then dragging = true; startIn = i.Position; startCenter = Win.AbsolutePosition + Win.AbsoluteSize / 2 end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d, sz = i.Position - startIn, Screen.AbsoluteSize
            local c = startCenter + Vector2.new(d.X, d.Y)
            Win.Position = UDim2.fromScale(math.clamp(c.X / sz.X, 0.05, 0.95), math.clamp(c.Y / sz.Y, 0.05, 0.95))
        end
    end)
    bind(UIS.InputEnded, function(i) if isPointer(i) then dragging = false end end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  TOASTS
-- ═══════════════════════════════════════════════════════════════════════
local ToastStack = new("Frame", { Parent = Screen, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(280, 400), BackgroundTransparency = 1 }, {
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right }),
})
local toastN = 0
local function toast(text, color, icon, dur)
    color = color or T.accent; dur = dur or 3; toastN += 1
    local f = new("CanvasGroup", { Parent = ToastStack, Size = UDim2.fromOffset(270, 44), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = toastN, GroupTransparency = 1 }, { corner(10), stroke(color, 1.2, 0.2) })
    new("Frame", { Parent = f, Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 })
    new("TextLabel", { Parent = f, Size = UDim2.fromOffset(34, 44), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Text = icon or "ℹ", TextColor3 = color, Font = Enum.Font.GothamBlack, TextSize = 17 })
    local l = label(f, text, 12, T.text, UDim2.fromOffset(44, 0), UDim2.new(1, -52, 1, 0), Enum.Font.GothamMedium)
    l.TextWrapped = true; l.TextTruncate = Enum.TextTruncate.None
    tween(f, 0.2, { GroupTransparency = 0 })
    task.delay(dur, function()
        if f and f.Parent then
            tween(f, 0.25, { GroupTransparency = 1 }); task.wait(0.28); f:Destroy()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  SIDEBAR
-- ═══════════════════════════════════════════════════════════════════════
local Sidebar = new("Frame", { Parent = Win, Position = UDim2.fromOffset(10, 56), Size = UDim2.fromOffset(124, 474), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, { corner(12), stroke(T.line, 1, 0.5) })
local navBtns = {}
for i, n in ipairs(NAV) do
    local b = new("TextButton", {
        Parent = Sidebar, Position = UDim2.fromOffset(8, 10 + (i - 1) * 44), Size = UDim2.fromOffset(108, 38),
        BackgroundColor3 = n.color, BackgroundTransparency = 1, Text = "  " .. n.icon .. "  " .. n.label,
        TextColor3 = T.sub, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false, BorderSizePixel = 0,
    }, { corner(9) })
    local bar = new("Frame", { Parent = b, Size = UDim2.fromOffset(3, 18), Position = UDim2.new(0, 0, 0.5, -9), BackgroundColor3 = n.color, BorderSizePixel = 0, Visible = false }, { corner(2) })
    b.MouseEnter:Connect(function() if S.tab ~= n.id then tween(b, 0.1, { BackgroundTransparency = 0.88 }) end end)
    b.MouseLeave:Connect(function() if S.tab ~= n.id then tween(b, 0.1, { BackgroundTransparency = 1 }) end end)
    navBtns[n.id] = { btn = b, bar = bar, nav = n }
end
local StatsL = label(Sidebar, "", 10, T.dim, UDim2.new(0, 10, 1, -44), UDim2.new(1, -20, 0, 36), Enum.Font.Gotham)
StatsL.TextWrapped = true; StatsL.TextYAlignment = Enum.TextYAlignment.Bottom
local function refreshStats() StatsL.Text = "Equipped slots: " .. countEquipped() .. "/8\nFavorites: " .. #DB.favs end

-- ═══════════════════════════════════════════════════════════════════════
--  CONTENT COLUMN
-- ═══════════════════════════════════════════════════════════════════════
local Content = new("Frame", { Parent = Win, Position = UDim2.fromOffset(142, 56), Size = UDim2.fromOffset(366, 474), BackgroundTransparency = 1 })
local HeadT = label(Content, "", 16, T.text, UDim2.fromOffset(2, 0), UDim2.new(1, 0, 0, 22), Enum.Font.GothamBlack)
local HeadS = label(Content, "", 10, T.dim, UDim2.fromOffset(2, 22), UDim2.new(1, 0, 0, 14), Enum.Font.Gotham)

local SearchRow = new("Frame", { Parent = Content, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 })
local SBox = new("TextBox", {
    Parent = SearchRow, Size = UDim2.new(1, -70, 1, 0), BackgroundColor3 = T.panel2, TextColor3 = T.text,
    PlaceholderText = "Search animation bundles…", PlaceholderColor3 = T.dim, Text = "", Font = Enum.Font.Gotham,
    TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
}, { corner(9), stroke(T.line, 1, 0.3), pad(12, 0, 8, 0) })
local SBtn = button(SearchRow, "Search", T.accent, UDim2.fromOffset(64, 32), UDim2.new(1, -64, 0, 0), 12)

local List = new("ScrollingFrame", {
    Parent = Content, Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 1, -120), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent2, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, {
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
    pad(0, 2, 4, 6),
})

local LoadF = new("Frame", { Parent = Content, Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 1, -120), BackgroundColor3 = T.bg, BackgroundTransparency = 0.15, Visible = false, ZIndex = 5, BorderSizePixel = 0 }, { corner(10) })
new("TextLabel", { Parent = LoadF, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "⟳  Loading…", TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 15, ZIndex = 6 })

local Pager = new("Frame", { Parent = Content, Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 })
local PrevBtn = button(Pager, "◄  Back", T.panel3, UDim2.fromOffset(84, 30), UDim2.fromOffset(0, 1), 11)
local NextBtn = button(Pager, "Next  ►", T.panel3, UDim2.fromOffset(84, 30), UDim2.new(1, -84, 0, 1), 11)
local PageLbl = label(Pager, "Page 1", 11, T.sub, UDim2.fromOffset(88, 0), UDim2.new(1, -176, 1, 0), Enum.Font.GothamMedium)
PageLbl.TextXAlignment = Enum.TextXAlignment.Center

-- ═══════════════════════════════════════════════════════════════════════
--  RIGHT PANEL
-- ═══════════════════════════════════════════════════════════════════════
local Right = new("Frame", { Parent = Win, Position = UDim2.fromOffset(516, 56), Size = UDim2.fromOffset(354, 474), BackgroundTransparency = 1 })

local VPOut = new("Frame", { Parent = Right, Size = UDim2.new(1, 0, 0, 196), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, { corner(14), stroke(T.accent, 1.2, 0.5) })
local VF = new("ViewportFrame", { Parent = VPOut, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = rgb(7, 9, 15), BorderSizePixel = 0, Ambient = rgb(170, 170, 185), LightColor = rgb(255, 255, 255) }, { corner(11) })
local Badge = new("Frame", { Parent = VPOut, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(78, 20), BackgroundColor3 = T.bg, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 3 }, { corner(6) })
new("TextLabel", { Parent = Badge, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "● PREVIEW", TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 9, ZIndex = 4 })

local StatF = new("Frame", { Parent = Right, Position = UDim2.fromOffset(0, 202), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, { corner(8), stroke(T.line, 1, 0.5) })
local StatL = label(StatF, "Select a bundle to preview", 11, T.sub, UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0), Enum.Font.GothamMedium)
local function setStatus(text, loading)
    StatL.Text = (loading and "⟳  " or "") .. text
    StatL.TextColor3 = loading and T.accent or T.sub
end

local EqF = new("Frame", { Parent = Right, Position = UDim2.fromOffset(0, 234), Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, { corner(10), stroke(T.good, 1, 0.6) })
local EqSlotL = label(EqF, "", 10, T.good, UDim2.fromOffset(12, 5), UDim2.new(1, -110, 0, 13), Enum.Font.GothamBold)
local EqNameL = label(EqF, "", 13, T.text, UDim2.fromOffset(12, 20), UDim2.new(1, -110, 0, 18), Enum.Font.GothamBold)
local RstBtn = button(EqF, "↩ Default", rgb(150, 70, 30), UDim2.fromOffset(84, 26), UDim2.new(1, -92, 0.5, -13), 11)

local SlotGrid = new("Frame", { Parent = Right, Position = UDim2.fromOffset(0, 286), Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1 }, {
    new("UIGridLayout", { CellSize = UDim2.fromOffset(83, 44), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local slotBtns, slotStroke = {}, {}
for i, s in ipairs(SLOTS) do
    local b = new("TextButton", {
        Parent = SlotGrid, LayoutOrder = i, BackgroundColor3 = T.panel2, Text = s.icon .. "\n" .. s.label,
        TextColor3 = T.dim, Font = Enum.Font.GothamBold, TextSize = 11, AutoButtonColor = false, BorderSizePixel = 0,
    }, { corner(9) })
    slotStroke[s.key] = stroke(T.line, 1.5, 0.6); slotStroke[s.key].Parent = b
    new("Frame", { Parent = b, Name = "Dot", Size = UDim2.fromOffset(7, 7), Position = UDim2.new(1, -11, 0, 4), BackgroundColor3 = T.good, BackgroundTransparency = 1, BorderSizePixel = 0 }, { corner(4) })
    slotBtns[s.key] = b
end

local Act = new("Frame", { Parent = Right, Position = UDim2.fromOffset(0, 386), Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1 })
local WearSelBtn = button(Act, "▶  Wear Slot", T.accent, UDim2.fromOffset(174, 34), UDim2.fromOffset(0, 0), 12)
local WearAllBtn = button(Act, "▶▶  Wear All", T.good, UDim2.fromOffset(174, 34), UDim2.fromOffset(180, 0), 12)
local FavBtn = button(Act, "☆  Favorite", T.panel3, UDim2.fromOffset(174, 34), UDim2.fromOffset(0, 42), 12)
local AddBldBtn = button(Act, "＋  Add to Builder", T.warn, UDim2.fromOffset(174, 34), UDim2.fromOffset(180, 42), 12)

-- ═══════════════════════════════════════════════════════════════════════
--  PREVIEW
-- ═══════════════════════════════════════════════════════════════════════
local function stopPreview()
    if S.track then pcall(function() S.track:Stop() end); S.track = nil end
end

local function buildRig()
    if S.vpConn then S.vpConn:Disconnect(); S.vpConn = nil end
    if S.wm then S.wm:Destroy(); S.wm = nil end
    if S.cam then S.cam:Destroy(); S.cam = nil end
    local char = LP.Character; if not char then return nil end
    char.Archivable = true
    local clone = char:Clone(); if not clone then return nil end
    local hum = clone:FindFirstChildOfClass("Humanoid"); local root = clone:FindFirstChild("HumanoidRootPart")
    if not hum or not root then clone:Destroy(); return nil end
    local animate = clone:FindFirstChild("Animate"); if animate then animate.Disabled = true end
    root.Anchored = true
    S.wm = new("WorldModel", { Parent = VF }); clone.Parent = S.wm
    clone:PivotTo(CFrame.new(0, 0, 0))
    S.cam = new("Camera", { Parent = VF, FieldOfView = 35, CFrame = CFrame.lookAt(Vector3.new(0, 0.5, 10), Vector3.new(0, 0, 0)) })
    VF.CurrentCamera = S.cam
    local ang = math.pi
    S.vpConn = RunService.RenderStepped:Connect(function(dt)
        if clone.Parent then ang += dt * 0.55; clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, ang, 0)) end
    end)
    return hum:FindFirstChildOfClass("Animator") or new("Animator", { Parent = hum })
end

local function playPreview(animId, gen)
    stopPreview()
    local animator = buildRig(); if not animator then return false end
    local anim = new("Animation", { AnimationId = animId })
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then return false end
    track.Looped = true; track:Play()
    local t0 = tick()
    while track.Length == 0 and tick() - t0 < 4 do task.wait(0.1) end
    if gen ~= S.gen then pcall(function() track:Stop() end); return false end
    if track.Length == 0 then pcall(function() track:Stop() end); return false end
    S.track = track; return true
end

local function previewSlot(item, slotKey)
    S.gen += 1; local gen = S.gen
    stopPreview()
    local s = SLOT[slotKey]
    setStatus(trunc(S.bundleName, 18) .. " • " .. s.label, true)
    task.spawn(function()
        local data
        for i = 1, 3 do
            data = fetchAnim(item, slotKey)
            if data or gen ~= S.gen then break end
            task.wait(0.6 * i)
        end
        if gen ~= S.gen then return end
        if not data then setStatus("Could not resolve animation"); return end
        local ok = playPreview(data.AnimationId, gen)
        if gen == S.gen then setStatus(ok and (trunc(S.bundleName, 18) .. " • " .. s.label) or "Preview failed") end
    end)
end

local function previewId(id)
    S.gen += 1; local gen = S.gen
    stopPreview(); setStatus("Preview ID " .. id, true)
    task.spawn(function()
        local ok = playPreview("rbxassetid://" .. id, gen)
        if gen == S.gen then
            setStatus(ok and ("Previewing ID " .. id) or "Preview failed (invalid or private ID?)")
            if not ok then toast("Could not play ID " .. id, T.bad, "✕") end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  BUNDLE LOGIC
-- ═══════════════════════════════════════════════════════════════════════
local function getBundle(id)
    if S.bundleCache[id] then return S.bundleCache[id] end
    local ok, res = pcall(function() return AssetService:GetBundleDetailsAsync(id) end)
    if ok and res and res.Items then S.bundleCache[id] = res; return res end
    return nil
end

local function mapItems(res)
    local m = {}
    for _, it in ipairs(res.Items or {}) do
        local lt = string.lower(it.AssetType or "")
        if lt == "swimanimation" then m.swimanimation = it; m.swimidleanimation = it
        elseif SLOT[lt] then m[lt] = it end
    end
    return m
end

local render, refreshPanel
local RENDER = {}

local function afterChange()
    refreshPanel(); refreshStats()
    if S.tab == "Current" or S.tab == "Builder" then render(true) end
end

local function wearBundle(id)
    local res = getBundle(id); if not res then return 0 end
    local items, n = mapItems(res), 0
    for _, s in ipairs(SLOTS) do
        local it = items[s.key]
        if it then
            local d = fetchAnim(it, s.key)
            if d and applySlot(s.key, d) then n += 1 end
        end
    end
    return n
end

local function isFav(id) for _, f in ipairs(DB.favs) do if tostring(f.id) == tostring(id) then return true end end; return false end
local function addFav(id, name) if not isFav(id) then table.insert(DB.favs, { id = id, name = name, time = os.time() }); save() end end
local function remFav(id)
    for i, f in ipairs(DB.favs) do if tostring(f.id) == tostring(id) then table.remove(DB.favs, i); save(); return end end
end

local function highlightCards()
    for id, c in pairs(S.cardRefs) do
        if c.Parent then
            local st = c:FindFirstChildOfClass("UIStroke")
            if st then
                local sel = (id == S.bundleId)
                st.Color = sel and T.accent or T.line; st.Transparency = sel and 0.1 or 0.5
            end
        end
    end
end

local function inspect(id, name)
    S.bundleId = id; S.bundleName = name or "Bundle"; S.items = {}
    DB.ui.bundleId = id; DB.ui.bundleName = S.bundleName; save()
    setStatus(trunc(S.bundleName, 18) .. " • loading", true)
    refreshPanel(); highlightCards()
    task.spawn(function()
        local res = getBundle(id)
        if S.bundleId ~= id then return end
        if not res then setStatus("Failed to load bundle"); toast("Failed to load bundle", T.bad, "✕"); return end
        S.items = mapItems(res)
        if not S.items[S.slot] then
            for _, s in ipairs(SLOTS) do if S.items[s.key] then S.slot = s.key; break end end
        end
        refreshPanel()
        if S.items[S.slot] then previewSlot(S.items[S.slot], S.slot)
        else setStatus(trunc(S.bundleName, 18) .. " • no preview") end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  PANEL REFRESH + BUTTONS
-- ═══════════════════════════════════════════════════════════════════════
refreshPanel = function()
    for _, s in ipairs(SLOTS) do
        local b, st = slotBtns[s.key], slotStroke[s.key]
        local has, sel = S.items[s.key] ~= nil, (s.key == S.slot)
        b.BackgroundColor3 = sel and s.color or T.panel2
        b.TextColor3 = sel and T.white or (has and s.color or T.dim)
        st.Color = has and s.color or T.line
        st.Transparency = sel and 1 or (has and 0.25 or 0.6)
        b.Dot.BackgroundTransparency = DB.equipped[s.key] and 0 or 1
    end
    local cur = SLOT[S.slot]
    local eq = DB.equipped[S.slot]
    EqSlotL.Text = "🎬  " .. cur.label .. " slot"
    EqNameL.Text = eq and trunc(eq.Name, 24) or "Not equipped"
    EqNameL.TextColor3 = eq and T.good or T.dim
    setEnabled(RstBtn, eq ~= nil)
    setEnabled(WearSelBtn, S.items[S.slot] ~= nil)
    setEnabled(WearAllBtn, next(S.items) ~= nil)
    setEnabled(AddBldBtn, S.items[S.slot] ~= nil)
    setEnabled(FavBtn, S.bundleId ~= nil)
    if S.bundleId and isFav(S.bundleId) then
        FavBtn.Text = "★  In Favorites"; FavBtn:SetAttribute("col", rgb(90, 72, 8))
        if FavBtn:GetAttribute("on") then FavBtn.BackgroundColor3 = rgb(90, 72, 8); FavBtn:SetAttribute("base", rgb(90, 72, 8)) end
        FavBtn.TextColor3 = T.gold
    else
        FavBtn.Text = "☆  Favorite"; FavBtn:SetAttribute("col", T.panel3)
        if FavBtn:GetAttribute("on") then FavBtn.BackgroundColor3 = T.panel3; FavBtn:SetAttribute("base", T.panel3) end
        FavBtn.TextColor3 = T.white
    end
    if S.slotHint and S.slotHint.Parent then
        S.slotHint.Text = "Target slot:  " .. cur.icon .. " " .. cur.label .. "   (change in the panel on the right)"
    end
end

for _, s in ipairs(SLOTS) do
    slotBtns[s.key].MouseButton1Click:Connect(function()
        S.slot = s.key; DB.ui.slot = s.key; save(); refreshPanel()
        if S.items[s.key] then previewSlot(S.items[s.key], s.key) end
    end)
end

click(WearSelBtn, function()
    local item, key = S.items[S.slot], S.slot
    if not item then return end
    setEnabled(WearSelBtn, false); WearSelBtn.Text = "Fetching…"
    task.spawn(function()
        local d = fetchAnim(item, key)
        if d and applySlot(key, d) then toast(SLOT[key].label .. " applied", T.good, "✓")
        else toast("Could not apply " .. SLOT[key].label, T.bad, "✕") end
        WearSelBtn.Text = "▶  Wear Slot"; afterChange()
    end)
end)

click(WearAllBtn, function()
    local id = S.bundleId; if not id then return end
    setEnabled(WearAllBtn, false); WearAllBtn.Text = "Fetching…"
    task.spawn(function()
        local n = wearBundle(id)
        toast(n > 0 and ("Applied " .. n .. " animations") or "Nothing applied", n > 0 and T.good or T.bad, n > 0 and "▶▶" or "✕")
        WearAllBtn.Text = "▶▶  Wear All"; afterChange()
    end)
end)

click(FavBtn, function()
    if not S.bundleId then return end
    if isFav(S.bundleId) then remFav(S.bundleId); toast("Removed from Favorites", T.sub, "☆", 2)
    else addFav(S.bundleId, S.bundleName); toast("Added: " .. trunc(S.bundleName, 18), T.gold, "★", 2) end
    refreshPanel(); refreshStats()
    if S.tab == "Favorites" or S.tab == "Browse" then render(true) end
end)

click(AddBldBtn, function()
    local item, key = S.items[S.slot], S.slot
    if not item then return end
    setEnabled(AddBldBtn, false); AddBldBtn.Text = "Fetching…"
    local bname, bid = S.bundleName, S.bundleId
    task.spawn(function()
        local d = fetchAnim(item, key)
        if d then
            DB.builder[key] = { Name = d.Name, AnimationId = d.AnimationId, Bundle = bname, BundleId = bid }; save()
            toast(SLOT[key].label .. " → Builder", T.warn, "＋", 2)
        else toast("Failed to fetch " .. SLOT[key].label, T.bad, "✕") end
        AddBldBtn.Text = "＋  Add to Builder"; refreshPanel()
        if S.tab == "Builder" then render(true) end
    end)
end)

click(RstBtn, function()
    resetSlot(S.slot); toast(SLOT[S.slot].label .. " → default", T.warn, "↩", 2); afterChange()
end)

-- ═══════════════════════════════════════════════════════════════════════
--  MODAL (имя сета)
-- ═══════════════════════════════════════════════════════════════════════
local Modal = new("Frame", { Parent = Win, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, Visible = false, ZIndex = 50, Active = true, BorderSizePixel = 0 })
local MBox = new("Frame", { Parent = Modal, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(330, 150), BackgroundColor3 = T.panel, BorderSizePixel = 0 }, { corner(14), stroke(T.accent2, 1.5, 0.2) })
local MTitle = label(MBox, "Name your set", 14, T.text, UDim2.fromOffset(16, 14), UDim2.new(1, -32, 0, 20), Enum.Font.GothamBold)
local MInput = new("TextBox", { Parent = MBox, Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 0, 34), BackgroundColor3 = T.panel2, TextColor3 = T.text, PlaceholderText = "Set name…", PlaceholderColor3 = T.dim, Text = "", Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0 }, { corner(9), stroke(T.line, 1, 0.3), pad(10, 0, 10, 0) })
local MOk = button(MBox, "✓  Save", T.accent2, UDim2.fromOffset(142, 32), UDim2.fromOffset(16, 102), 12)
local MCancel = button(MBox, "Cancel", T.panel3, UDim2.fromOffset(142, 32), UDim2.new(1, -158, 0, 102), 12)
local modalCB
local function prompt(title, default, cb)
    MTitle.Text = title; MInput.Text = default or ""; modalCB = cb; Modal.Visible = true
    task.defer(function() MInput:CaptureFocus() end)
end
MOk.MouseButton1Click:Connect(function()
    Modal.Visible = false
    local cb = modalCB; modalCB = nil
    if cb then cb(MInput.Text ~= "" and MInput.Text or ("My Set " .. (#DB.presets + 1))) end
end)
MCancel.MouseButton1Click:Connect(function() Modal.Visible = false; modalCB = nil end)

-- ═══════════════════════════════════════════════════════════════════════
--  LIST HELPERS
-- ═══════════════════════════════════════════════════════════════════════
local order = 0
local function clearList()
    for _, c in ipairs(List:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    order = 0; S.cardRefs = {}; S.slotHint = nil
end
local function card(h, strokeCol)
    order += 1
    return new("Frame", { Parent = List, Size = UDim2.new(1, -2, 0, h), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = order }, { corner(11), stroke(strokeCol or T.line, 1, 0.5) })
end
local function section(text)
    order += 1
    local l = label(List, text, 11, T.sub, nil, UDim2.new(1, 0, 0, 18), Enum.Font.GothamBold)
    l.LayoutOrder = order; return l
end
local function empty(text)
    local c = card(80)
    local l = label(c, text, 12, T.dim, UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), Enum.Font.Gotham)
    l.TextWrapped = true; l.TextTruncate = Enum.TextTruncate.None; l.TextXAlignment = Enum.TextXAlignment.Center
end
local function thumb(parent, id, size, pos)
    return new("ImageLabel", { Parent = parent, Size = UDim2.fromOffset(size, size), Position = pos, BackgroundColor3 = T.panel3, BorderSizePixel = 0, Image = "rbxthumb://type=BundleThumbnail&id=" .. tostring(id) .. "&w=150&h=150" }, { corner(8) })
end
local function chip(parent, slotKey, w, h, pos)
    local s = SLOT[slotKey]
    local f = new("Frame", { Parent = parent, Size = UDim2.fromOffset(w or 40, h or 18), Position = pos or UDim2.new(), BackgroundColor3 = s.color, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, { corner(5) })
    new("TextLabel", { Parent = f, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = s.label, TextColor3 = T.white, Font = Enum.Font.GothamBold, TextSize = 9 })
    return f
end
local function iconBox(parent, slotKey, size, pos)
    local s = SLOT[slotKey]
    local f = new("Frame", { Parent = parent, Size = UDim2.fromOffset(size, size), Position = pos, BackgroundColor3 = s.color, BackgroundTransparency = 0.78, BorderSizePixel = 0 }, { corner(10), stroke(s.color, 1, 0.5) })
    new("TextLabel", { Parent = f, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = s.icon, TextSize = size * 0.5, Font = Enum.Font.GothamBold })
    return f
end
local function copyText(txt)
    if typeof(setclipboard) == "function" then setclipboard(txt); toast("Copied: " .. txt, T.good, "⧉", 2)
    else toast("Clipboard not supported", T.bad, "✕", 2) end
end

-- ═══════════════════════════════════════════════════════════════════════
--  BROWSE
-- ═══════════════════════════════════════════════════════════════════════
local function updatePager()
    if S.tab ~= "Browse" then return end
    local total = math.max(1, math.ceil(#S.results / S.perPage))
    local more = S.pages and not S.pages.IsFinished
    PageLbl.Text = ("Page %d / %d%s"):format(S.page, total, more and "+" or "")
    setEnabled(PrevBtn, S.page > 1)
    setEnabled(NextBtn, S.page < total or (more and true or false))
end

local function bundleRow(b, h, strokeCol)
    local c = card(h, strokeCol); S.cardRefs[b.Id or b.id] = c
    return c
end

local function wearButtonFlow(btn, id, name, restoreText)
    setEnabled(btn, false); btn.Text = "…"
    task.spawn(function()
        local n = wearBundle(id)
        toast(n > 0 and ("Wearing " .. trunc(name, 16) .. " (" .. n .. ")") or "Nothing applied", n > 0 and T.good or T.bad, n > 0 and "▶" or "✕")
        if btn and btn.Parent then setEnabled(btn, true); btn.Text = restoreText end
        afterChange()
    end)
end

RENDER.Browse = function()
    if #S.results == 0 then empty(S.loading and "Loading…" or "No results.\nTry another search."); return end
    local s, e = (S.page - 1) * S.perPage + 1, math.min(S.page * S.perPage, #S.results)
    for i = s, e do
        local b = S.results[i]
        if b then
            local c = card(64); S.cardRefs[b.Id] = c
            thumb(c, b.Id, 48, UDim2.fromOffset(8, 8))
            label(c, b.Name or "?", 13, T.text, UDim2.fromOffset(64, 11), UDim2.new(1, -176, 0, 18), Enum.Font.GothamBold)
            label(c, "ID " .. tostring(b.Id), 10, T.dim, UDim2.fromOffset(64, 33), UDim2.new(1, -176, 0, 14), Enum.Font.Gotham)
            local hit = new("TextButton", { Parent = c, BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, -116, 1, 0) })
            local star = new("TextButton", { Parent = c, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -112, 0.5, -13), BackgroundTransparency = 1, Text = isFav(b.Id) and "★" or "☆", TextColor3 = isFav(b.Id) and T.gold or T.dim, Font = Enum.Font.GothamBlack, TextSize = 20, AutoButtonColor = false })
            local wear = button(c, "▶ Wear", T.good, UDim2.fromOffset(72, 30), UDim2.new(1, -80, 0.5, -15), 11)
            hit.MouseButton1Click:Connect(function() inspect(b.Id, b.Name) end)
            star.MouseButton1Click:Connect(function()
                if isFav(b.Id) then remFav(b.Id); star.Text = "☆"; star.TextColor3 = T.dim
                else addFav(b.Id, b.Name); star.Text = "★"; star.TextColor3 = T.gold; toast("Added: " .. trunc(b.Name, 18), T.gold, "★", 2) end
                refreshStats(); refreshPanel()
            end)
            click(wear, function() wearButtonFlow(wear, b.Id, b.Name, "▶ Wear") end)
        end
    end
    highlightCards()
end

local function doSearch(q)
    S.page = 1; S.results = {}; S.pages = nil
    S.searchId += 1; local sid = S.searchId
    S.loading = true; LoadF.Visible = (S.tab == "Browse")
    task.spawn(function()
        local ok, pages = pcall(function()
            local p = CatalogSearchParams.new()
            p.SearchKeyword = q or ""; p.BundleTypes = { Enum.BundleType.Animations }; p.IncludeOffSale = true; p.Limit = 60
            pcall(function() p.SalesTypeFilter = Enum.SalesTypeFilter.All end)
            pcall(function() p.SortType = Enum.CatalogSortType.RecentlyCreated end)
            return AvatarEditor:SearchCatalog(p)
        end)
        if sid ~= S.searchId then return end
        S.loading = false; LoadF.Visible = false
        if ok and pages then
            S.pages = pages; S.results = pages:GetCurrentPage()
        else toast("Search failed", T.bad, "✕") end
        if S.tab == "Browse" then render() end
    end)
end

SBtn.MouseButton1Click:Connect(function() doSearch(SBox.Text) end)
SBox.FocusLost:Connect(function(enter) if enter then doSearch(SBox.Text) end end)

click(PrevBtn, function() if S.page > 1 then S.page -= 1; render() end end)
click(NextBtn, function()
    if S.page * S.perPage < #S.results then S.page += 1; render()
    elseif S.pages and not S.pages.IsFinished then
        S.loading = true; LoadF.Visible = true
        local sid = S.searchId
        task.spawn(function()
            local ok = pcall(function() S.pages:AdvanceToNextPageAsync() end)
            if sid ~= S.searchId then return end
            S.loading = false; LoadF.Visible = false
            if ok then
                for _, v in ipairs(S.pages:GetCurrentPage()) do table.insert(S.results, v) end
                if S.page * S.perPage < #S.results then S.page += 1 end
                render()
            else toast("Could not load more", T.bad, "✕") end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════
--  FAVORITES
-- ═══════════════════════════════════════════════════════════════════════
RENDER.Favorites = function()
    if #DB.favs == 0 then empty("No favorites yet.\nPick a bundle → ☆ Favorite"); return end
    local sorted = {}
    for _, f in ipairs(DB.favs) do table.insert(sorted, f) end
    table.sort(sorted, function(a, b) return (a.time or 0) > (b.time or 0) end)
    for _, fav in ipairs(sorted) do
        local c = card(60, T.gold); S.cardRefs[fav.id] = c
        thumb(c, fav.id, 44, UDim2.fromOffset(8, 8))
        label(c, fav.name or "?", 13, T.text, UDim2.fromOffset(60, 11), UDim2.new(1, -226, 0, 18), Enum.Font.GothamBold)
        label(c, "Bundle " .. tostring(fav.id), 10, T.dim, UDim2.fromOffset(60, 32), UDim2.new(1, -226, 0, 14), Enum.Font.Gotham)
        local open = button(c, "Open", T.accent, UDim2.fromOffset(54, 28), UDim2.new(1, -156, 0.5, -14), 11)
        local wear = button(c, "▶ Wear", T.good, UDim2.fromOffset(62, 28), UDim2.new(1, -98, 0.5, -14), 11)
        local del = button(c, "✕", rgb(130, 30, 42), UDim2.fromOffset(28, 28), UDim2.new(1, -34, 0.5, -14), 12)
        open.MouseButton1Click:Connect(function() inspect(fav.id, fav.name) end)
        click(wear, function() wearButtonFlow(wear, fav.id, fav.name, "▶ Wear") end)
        del.MouseButton1Click:Connect(function()
            remFav(fav.id); refreshPanel(); refreshStats(); toast("Removed", T.sub, "☆", 2); render(true)
        end)
    end
    highlightCards()
end

-- ═══════════════════════════════════════════════════════════════════════
--  BUILDER
-- ═══════════════════════════════════════════════════════════════════════
RENDER.Builder = function()
    local filled = 0
    for _, s in ipairs(SLOTS) do if DB.builder[s.key] then filled += 1 end end

    local h = card(48, T.warn)
    label(h, "Compose your own set", 13, T.text, UDim2.fromOffset(12, 7), UDim2.new(1, -90, 0, 18), Enum.Font.GothamBold)
    label(h, "Browse → pick slot → ＋ Add to Builder", 10, T.dim, UDim2.fromOffset(12, 26), UDim2.new(1, -90, 0, 14), Enum.Font.Gotham)
    local cnt = label(h, filled .. "/8", 18, T.warn, UDim2.new(1, -66, 0, 0), UDim2.fromOffset(56, 48), Enum.Font.GothamBlack)
    cnt.TextXAlignment = Enum.TextXAlignment.Center

    for _, s in ipairs(SLOTS) do
        local d = DB.builder[s.key]
        local row = card(50, d and s.color or T.line)
        iconBox(row, s.key, 34, UDim2.fromOffset(8, 8))
        if d then
            label(row, d.Name or "?", 12, T.text, UDim2.fromOffset(52, 7), UDim2.new(1, -96, 0, 16), Enum.Font.GothamBold)
            label(row, "📦 " .. (d.Bundle or "?"), 10, s.color, UDim2.fromOffset(52, 26), UDim2.new(1, -96, 0, 14), Enum.Font.Gotham)
            local x = button(row, "✕", rgb(130, 30, 42), UDim2.fromOffset(26, 26), UDim2.new(1, -34, 0.5, -13), 12)
            x.MouseButton1Click:Connect(function() DB.builder[s.key] = nil; save(); render(true) end)
        else
            label(row, s.label .. " — empty", 11, T.dim, UDim2.fromOffset(52, 0), UDim2.new(1, -60, 1, 0), Enum.Font.Gotham)
        end
    end

    order += 1
    local bar = new("Frame", { Parent = List, Size = UDim2.new(1, -2, 0, 34), BackgroundTransparency = 1, LayoutOrder = order })
    local save_ = button(bar, "💾 Save Set", T.accent2, UDim2.fromOffset(112, 34), UDim2.fromOffset(0, 0), 11)
    local apply = button(bar, "▶ Apply Now", T.good, UDim2.fromOffset(112, 34), UDim2.fromOffset(118, 0), 11)
    local clear = button(bar, "🗑 Clear", T.panel3, UDim2.fromOffset(112, 34), UDim2.fromOffset(236, 0), 11)
    if filled == 0 then setEnabled(save_, false); setEnabled(apply, false); setEnabled(clear, false) end

    click(save_, function()
        prompt("Name your set", "My Set " .. (#DB.presets + 1), function(name)
            local snap = {}
            for _, s in ipairs(SLOTS) do
                local d = DB.builder[s.key]
                if d and d.AnimationId and d.AnimationId ~= "" then snap[s.key] = { Name = d.Name, AnimationId = d.AnimationId } end
            end
            table.insert(DB.presets, { name = name, slots = snap, time = os.time() }); save()
            toast("'" .. trunc(name, 16) .. "' saved", T.accent2, "💾", 3)
        end)
    end)
    click(apply, function()
        local n = 0
        for _, s in ipairs(SLOTS) do
            local d = DB.builder[s.key]
            if d and applySlot(s.key, d) then n += 1 end
        end
        toast("Applied " .. n .. " slots", T.good, "▶", 2); afterChange()
    end)
    click(clear, function() DB.builder = {}; save(); render(true) end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  SETS
-- ═══════════════════════════════════════════════════════════════════════
RENDER.Sets = function()
    if #DB.presets == 0 then empty("No sets yet.\n\n① Add slots to Builder\n② Builder → 💾 Save Set"); return end
    for idx, p in ipairs(DB.presets) do
        local list, n = {}, 0
        for _, s in ipairs(SLOTS) do
            local d = p.slots and p.slots[s.key]
            if d and d.AnimationId and d.AnimationId ~= "" then n += 1; table.insert(list, s.key) end
        end
        local c = card(104, T.accent2)
        label(c, p.name or "Set", 14, T.text, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 18), Enum.Font.GothamBlack)
        label(c, n .. " animations  •  " .. timeAgo(p.time), 10, T.accent2, UDim2.fromOffset(12, 28), UDim2.new(1, -24, 0, 14), Enum.Font.GothamBold)
        local chips = new("Frame", { Parent = c, Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 18), BackgroundTransparency = 1 }, {
            new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }),
        })
        for _, k in ipairs(list) do chip(chips, k, 38, 18) end
        local apply = button(c, "▶ Apply", T.good, UDim2.fromOffset(104, 28), UDim2.fromOffset(12, 70), 11)
        local edit = button(c, "✎ Edit", T.panel3, UDim2.fromOffset(104, 28), UDim2.fromOffset(122, 70), 11)
        local del = button(c, "✕ Delete", rgb(130, 30, 42), UDim2.fromOffset(104, 28), UDim2.fromOffset(232, 70), 11)
        click(apply, function()
            setEnabled(apply, false); apply.Text = "…"
            task.spawn(function()
                local k = 0
                for _, s in ipairs(SLOTS) do
                    local d = p.slots and p.slots[s.key]
                    if d and d.AnimationId and d.AnimationId ~= "" and applySlot(s.key, d) then k += 1 end
                end
                toast("'" .. trunc(p.name, 14) .. "' applied (" .. k .. ")", T.good, "▶")
                if apply.Parent then setEnabled(apply, true); apply.Text = "▶ Apply" end
                afterChange()
            end)
        end)
        edit.MouseButton1Click:Connect(function()
            DB.builder = {}
            for _, s in ipairs(SLOTS) do
                local d = p.slots and p.slots[s.key]
                if d then DB.builder[s.key] = { Name = d.Name, AnimationId = d.AnimationId, Bundle = p.name, BundleId = 0 } end
            end
            save(); toast("Loaded into Builder", T.warn, "✎", 2); S.setTab("Builder")
        end)
        del.MouseButton1Click:Connect(function() table.remove(DB.presets, idx); save(); toast("Set deleted", T.bad, "✕", 2); render(true) end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════
--  CURRENT
-- ═══════════════════════════════════════════════════════════════════════
RENDER.Current = function()
    local any = false
    for _, s in ipairs(SLOTS) do
        local d = DB.equipped[s.key]
        if d then
            any = true
            local c = card(56, s.color)
            iconBox(c, s.key, 40, UDim2.fromOffset(8, 8))
            label(c, d.Name or "?", 13, T.text, UDim2.fromOffset(56, 9), UDim2.new(1, -140, 0, 18), Enum.Font.GothamBold)
            local id = tostring(d.AnimationId or ""):match("%d+") or ""
            label(c, s.label .. (id ~= "" and ("  •  " .. id) or ""), 10, T.dim, UDim2.fromOffset(56, 30), UDim2.new(1, -140, 0, 14), Enum.Font.Gotham)
            local cp = button(c, "⧉", T.panel3, UDim2.fromOffset(28, 28), UDim2.new(1, -96, 0.5, -14), 13)
            local rs = button(c, "↩ Reset", rgb(150, 70, 30), UDim2.fromOffset(58, 28), UDim2.new(1, -64, 0.5, -14), 10)
            cp.MouseButton1Click:Connect(function() if id ~= "" then copyText("rbxassetid://" .. id) end end)
            rs.MouseButton1Click:Connect(function() resetSlot(s.key); toast(s.label .. " → default", T.warn, "↩", 2); afterChange() end)
        end
    end
    if not any then empty("Nothing equipped yet.\nBrowse bundles → ▶ Wear"); return end
    order += 1
    local bar = new("Frame", { Parent = List, Size = UDim2.new(1, -2, 0, 34), BackgroundTransparency = 1, LayoutOrder = order })
    local all = button(bar, "↩  Reset ALL to default", rgb(150, 70, 30), UDim2.fromScale(1, 1), nil, 12)
    all.MouseButton1Click:Connect(function()
        for _, s in ipairs(SLOTS) do resetSlot(s.key) end
        DB.equipped = {}; save(); toast("All reset", T.warn, "↩"); afterChange()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════
--  BY ID
-- ═══════════════════════════════════════════════════════════════════════
local function addHistory(id, slot)
    for i = #DB.history, 1, -1 do
        if tostring(DB.history[i].id) == tostring(id) and DB.history[i].slot == slot then table.remove(DB.history, i) end
    end
    table.insert(DB.history, 1, { id = tostring(id), slot = slot, time = os.time() })
    while #DB.history > 8 do table.remove(DB.history) end
    save()
end

local function applyById(id, slot)
    local ok = applySlot(slot, { Name = "Custom " .. id, AnimationId = "rbxassetid://" .. id })
    if ok then addHistory(id, slot); toast(SLOT[slot].label .. " ← ID " .. id, T.cyan, "✓", 3)
    else toast("Failed to apply (no character?)", T.bad, "✕") end
    return ok
end

RENDER.ById = function()
    local c = card(160, T.cyan)
    label(c, "Animation asset ID or URL", 11, T.sub, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 14), Enum.Font.GothamBold)
    local box = new("TextBox", {
        Parent = c, Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 32), BackgroundColor3 = T.panel2,
        TextColor3 = T.text, PlaceholderText = "e.g. 656118852  or  rbxassetid://656118852", PlaceholderColor3 = T.dim,
        Text = S.idText, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
    }, { corner(8), stroke(T.line, 1, 0.3), pad(10, 0, 10, 0) })
    box:GetPropertyChangedSignal("Text"):Connect(function() S.idText = box.Text end)
    S.slotHint = label(c, "", 11, T.cyan, UDim2.fromOffset(12, 68), UDim2.new(1, -24, 0, 14), Enum.Font.GothamMedium)
    local apply = button(c, "▶  Apply", T.cyan, UDim2.fromOffset(150, 34), UDim2.fromOffset(10, 90), 12)
    local prev = button(c, "👁 Preview", T.panel3, UDim2.fromOffset(92, 34), UDim2.fromOffset(166, 90), 11)
    local bld = button(c, "＋ Builder", T.warn, UDim2.fromOffset(92, 34), UDim2.fromOffset(264, 90), 11)
    local tip = label(c, "Tip: use the Animation asset ID, not the bundle ID.", 10, T.dim, UDim2.fromOffset(12, 134), UDim2.new(1, -24, 0, 14), Enum.Font.Gotham)

    local function getId() return (box.Text:gsub("%s", "")):match("%d+") end
    click(apply, function()
        local id = getId(); if not id then toast("Enter a valid animation ID", T.bad, "!"); return end
        setEnabled(apply, false); apply.Text = "Applying…"
        task.spawn(function()
            applyById(id, S.slot)
            if apply.Parent then setEnabled(apply, true); apply.Text = "▶  Apply" end
            afterChange(); render(true)
        end)
    end)
    click(prev, function()
        local id = getId(); if not id then toast("Enter a valid animation ID", T.bad, "!"); return end
        previewId(id)
    end)
    click(bld, function()
        local id = getId(); if not id then toast("Enter a valid animation ID", T.bad, "!"); return end
        DB.builder[S.slot] = { Name = "Custom " .. id, AnimationId = "rbxassetid://" .. id, Bundle = "By ID", BundleId = 0 }; save()
        toast(SLOT[S.slot].label .. " → Builder", T.warn, "＋", 2)
    end)

    if #DB.history > 0 then
        section("RECENT")
        for i, e in ipairs(DB.history) do
            local r = card(42)
            chip(r, e.slot, 44, 20, UDim2.fromOffset(8, 11))
            label(r, "ID " .. tostring(e.id), 12, T.text, UDim2.fromOffset(60, 0), UDim2.new(1, -176, 1, 0), Enum.Font.GothamMedium)
            local use = button(r, "▶ Apply", T.accent, UDim2.fromOffset(66, 26), UDim2.new(1, -106, 0.5, -13), 10)
            local x = button(r, "✕", rgb(130, 30, 42), UDim2.fromOffset(26, 26), UDim2.new(1, -34, 0.5, -13), 11)
            local fill = new("TextButton", { Parent = r, BackgroundTransparency = 1, Text = "", Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -170, 1, 0) })
            fill.MouseButton1Click:Connect(function() box.Text = tostring(e.id) end)
            use.MouseButton1Click:Connect(function()
                S.slot = e.slot; DB.ui.slot = e.slot
                task.spawn(function() applyById(e.id, e.slot); afterChange(); render(true) end)
            end)
            x.MouseButton1Click:Connect(function() table.remove(DB.history, i); save(); render(true) end)
        end
    end
    refreshPanel()
end

-- ═══════════════════════════════════════════════════════════════════════
--  RENDER + TABS
-- ═══════════════════════════════════════════════════════════════════════
render = function(keep)
    local pos = List.CanvasPosition
    clearList()
    local fn = RENDER[S.tab]; if fn then fn() end
    if keep then task.defer(function() List.CanvasPosition = pos end) else List.CanvasPosition = Vector2.zero end
    updatePager()
end

local function setTab(id)
    S.tab = id; DB.ui.tab = id; save()
    for tid, o in pairs(navBtns) do
        local on = (tid == id)
        tween(o.btn, 0.15, { BackgroundTransparency = on and 0.8 or 1 })
        o.btn.TextColor3 = on and T.text or T.sub
        o.bar.Visible = on
        if on then HeadT.Text = o.nav.icon .. "  " .. o.nav.title; HeadS.Text = o.nav.sub; HeadT.TextColor3 = o.nav.color end
    end
    local browse = (id == "Browse")
    SearchRow.Visible = browse; Pager.Visible = browse
    List.Position = UDim2.fromOffset(0, browse and 82 or 46)
    List.Size = UDim2.new(1, 0, 1, browse and -120 or -46)
    LoadF.Position = List.Position; LoadF.Size = List.Size
    LoadF.Visible = browse and S.loading
    if browse and #S.results == 0 and not S.loading then doSearch("") end
    render()
end
S.setTab = setTab
for tid, o in pairs(navBtns) do o.btn.MouseButton1Click:Connect(function() setTab(tid) end) end

BtnClose.MouseButton1Click:Connect(function() Screen:Destroy() end)

-- ═══════════════════════════════════════════════════════════════════════
--  CHARACTER HANDLING
-- ═══════════════════════════════════════════════════════════════════════
local function onChar(char)
    task.spawn(function()
        local animate = char:WaitForChild("Animate", 10)
        local hum = char:WaitForChild("Humanoid", 10)
        if not animate or not hum then return end
        task.wait(0.8)
        captureDefaults(animate)
        for _, s in ipairs(SLOTS) do
            local d = DB.equipped[s.key]
            if d then setSlotAnim(char, s.key, d) end
        end
        if Screen.Parent then refreshPanel(); refreshStats() end
    end)
end
if LP.Character then onChar(LP.Character) end
bind(LP.CharacterAdded, onChar)

Screen.Destroying:Connect(function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    stopPreview()
    if S.vpConn then S.vpConn:Disconnect() end
end)

-- ═══════════════════════════════════════════════════════════════════════
--  BOOT
-- ═══════════════════════════════════════════════════════════════════════
do
    local target = UIScaleObj.Scale
    UIScaleObj.Scale = target * 0.92
    Win.BackgroundTransparency = 1
    tween(UIScaleObj, 0.3, { Scale = target })
    tween(Win, 0.3, { BackgroundTransparency = 0 })
end
refreshStats(); refreshPanel(); setTab(S.tab)
if S.bundleId then inspect(S.bundleId, S.bundleName) end
task.delay(0.6, function() toast("v4.0 loaded — RightShift to hide", T.accent, "▶", 3) end)
