-- 读书小宠物「云朵」和她的小屋
--
-- 规则（所有书加起来、每天重新算）：
--   只算真正往前读的新字：每秒最多算 30 字，翻得太快的不算；一次跳过 6000 字以上（从目录跳着翻）也不算。
--   今天读到 2000 字 → 一份零食；5000 字、1 万字 → 各一件家具摆饰；2 万字 → 一件稀有摆饰。
--   奖励先变成礼物盒，到小屋里拆开。家具一件件摆进屋里，从空房间慢慢变丰富。
--   好几天没读书，屋子会落灰、变旧（东西不会丢）；哪天读够 1000 字就打扫干净。
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local L = require("rb_i18n").L

local Pet = {}

Pet.TIERS = { 2000, 5000, 10000, 20000 }
Pet.CLEAN_CHARS = 1000      -- 一天读够这么多字，屋子就打扫干净
Pet.DUSTY_DAYS = 3          -- 几天没读书开始落灰
Pet.OLD_DAYS = 7            -- 几天没读书屋子变旧
Pet.RATE = 30               -- 每秒最多算多少字
Pet.MAX_JUMP = 6000         -- 一次往前超过这么多字，当成跳着翻，不算

-- MARK: 零食和家具

Pet.SNACKS = {
    { id = "cookie", name = "饼干" },
    { id = "cake", name = "草莓蛋糕" },
    { id = "pudding", name = "布丁" },
    { id = "candy", name = "糖果" },
    { id = "donut", name = "甜甜圈" },
    { id = "icecream", name = "冰淇淋" },
    { id = "milk", name = "牛奶" },
    { id = "onigiri", name = "饭团" },
}

-- 按顺序送：先铺地毯、放床，屋子一点点变满
Pet.ITEMS = {
    { id = "rug", name = "圆圆的地毯" },
    { id = "bed", name = "小床" },
    { id = "table", name = "小圆桌" },
    { id = "lamp", name = "台灯" },
    { id = "curtains", name = "窗帘" },
    { id = "painting", name = "挂画" },
    { id = "shelf", name = "书架" },
    { id = "plant", name = "小盆栽" },
    { id = "books", name = "一摞小书" },
    { id = "cushion", name = "爱心抱枕" },
    { id = "clock", name = "挂钟" },
    { id = "wallpaper", name = "花花墙纸" },
    { id = "floor", name = "木地板" },
    { id = "garland", name = "彩旗" },
    { id = "teacup", name = "小茶杯" },
    { id = "moon", name = "月亮挂饰" },
}

Pet.RARE = {
    { id = "chandelier", name = "水晶吊灯" },
    { id = "rainbow", name = "彩虹窗贴" },
    { id = "balloons", name = "爱心气球" },
    { id = "trophy", name = "金色奖杯" },
}

local function find(list, id)
    for _, it in ipairs(list) do
        if it.id == id then return it end
    end
end

function Pet.thingName(gift)
    local it = find(Pet.SNACKS, gift.id) or find(Pet.ITEMS, gift.id) or find(Pet.RARE, gift.id)
    return it and L(it.name) or gift.id
end

-- MARK: 日期

local function dayKey(t) return os.date("%Y-%m-%d", t or os.time()) end

local function dayTime(key)
    local y, m, d = (key or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

local function daysBetween(a, b)
    local ta, tb = dayTime(a), dayTime(b)
    if not ta or not tb then return 0 end
    return math.floor((tb - ta) / 86400 + 0.5)
end

-- MARK: 存档（KOReader 全局设置里的 readingbuddy_pet，所有书共用）

function Pet.state()
    local s = G_reader_settings:readSetting("readingbuddy_pet")
    if type(s) ~= "table" then s = {} end
    s.adopted = s.adopted or dayKey()
    s.days = s.days or {}
    s.tiers = s.tiers or {}
    s.snacks = s.snacks or {}
    s.owned = s.owned or {}
    s.gifts = s.gifts or {}
    s.fed_count = s.fed_count or 0
    local today = dayKey()
    if s.tier_day ~= today then
        s.tier_day = today
        s.tiers = {}
    end
    -- 只留最近 30 天的记录
    for k in pairs(s.days) do
        if daysBetween(k, today) > 30 then s.days[k] = nil end
    end
    return s
end

function Pet.save(s, flush)
    G_reader_settings:saveSetting("readingbuddy_pet", s)
    if flush then G_reader_settings:flush() end
end

function Pet.today(s) return s.days[dayKey()] or 0 end

--- 0 = 干干净净，1 = 落了点灰，2 = 旧旧的
function Pet.shabby(s)
    local base = s.adopted
    if s.last_active and s.last_active > base then base = s.last_active end
    local d = daysBetween(base, dayKey())
    if d >= Pet.OLD_DAYS then return 2 end
    if d >= Pet.DUSTY_DAYS then return 1 end
    return 0
end

function Pet.ownedCount(s)
    local n = 0
    for _ in pairs(s.owned) do n = n + 1 end
    return n
end

local function pending(s, id)
    for _, g in ipairs(s.gifts) do
        if g.id == id then return true end
    end
    return false
end

local function nextFrom(s, list)
    for _, it in ipairs(list) do
        if not s.owned[it.id] and not pending(s, it.id) then return it end
    end
end

local function giftFor(s, tier)
    local it
    if tier == 4 then it = nextFrom(s, Pet.RARE) or nextFrom(s, Pet.ITEMS)
    elseif tier >= 2 then it = nextFrom(s, Pet.ITEMS) end
    if it then return { t = "item", id = it.id } end
    return { t = "snack", id = Pet.SNACKS[math.random(#Pet.SNACKS)].id }
end

--- 记下新读的字。返回：这次新得到几个礼物盒、屋子是不是刚打扫干净
function Pet.addRead(n)
    if n <= 0 then return 0, false end
    local s = Pet.state()
    local was_shabby = Pet.shabby(s)
    local today = dayKey()
    s.days[today] = (s.days[today] or 0) + n
    local total = s.days[today]
    if total >= Pet.CLEAN_CHARS then s.last_active = today end
    local got = 0
    for i, t in ipairs(Pet.TIERS) do
        if total >= t and not s.tiers[i] then
            s.tiers[i] = true
            table.insert(s.gifts, giftFor(s, i))
            got = got + 1
        end
    end
    local cleaned = was_shabby > 0 and Pet.shabby(s) == 0
    Pet.save(s, got > 0 or cleaned)
    return got, cleaned
end

--- 拆一个礼物盒
function Pet.openGift()
    local s = Pet.state()
    local g = table.remove(s.gifts, 1)
    if not g then return end
    if g.t == "snack" then
        s.snacks[g.id] = (s.snacks[g.id] or 0) + 1
    else
        s.owned[g.id] = dayKey()
    end
    Pet.save(s, true)
    return g
end

function Pet.snackCount(s)
    local n = 0
    for _, c in pairs(s.snacks) do n = n + c end
    return n
end

function Pet.feed(id)
    local s = Pet.state()
    if (s.snacks[id] or 0) <= 0 then return false end
    s.snacks[id] = s.snacks[id] - 1
    if s.snacks[id] <= 0 then s.snacks[id] = nil end
    s.fed_day = dayKey()
    s.fed_snack = id
    s.fed_count = s.fed_count + 1
    Pet.save(s, true)
    return true
end

-- MARK: 画小屋（生成 SVG，KOReader 自带的 NanoSVG 能画）

local INK = "#574045"
local C = {
    pink = "#ffb8c9", rose = "#ff8ca8", yellow = "#ffe085", orange = "#ffbd6b", blue = "#bde0ff",
    mint = "#c2edd6", green = "#8cd18c", peach = "#ffdbb3", cream = "#fff7e8", lav = "#dbcfff",
    gray = "#ebe6ed", brown = "#cc946b", tan = "#edcfa1", patch = "#8c6b54", blush = "#ff8c9e",
    honey = "#db9e61", wall = "#fff4e6", floor = "#f3dfc9", wood = "#e8b98f", dust = "#b9aeb4",
}

local function n(v)
    local s = string.format("%.1f", v):gsub("%.0$", "")
    return s
end

local Svg = {}
Svg.__index = Svg

local function newSvg() return setmetatable({ out = {} }, Svg) end

function Svg:add(s) table.insert(self.out, s) end

local function strokeAttr(fill, line, color)
    return string.format(' fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"',
        fill or "none", line and line > 0 and (color or INK) or "none", n(line or 0))
end

function Svg:ellipse(cx, cy, rx, ry, fill, line, extra)
    self:add(string.format('<ellipse cx="%s" cy="%s" rx="%s" ry="%s"%s%s/>', n(cx), n(cy), n(rx), n(ry),
        strokeAttr(fill, line), extra or ""))
end

function Svg:rect(x, y, w, h, r, fill, line, extra)
    self:add(string.format('<rect x="%s" y="%s" width="%s" height="%s" rx="%s"%s%s/>', n(x), n(y), n(w), n(h), n(r or 0),
        strokeAttr(fill, line), extra or ""))
end

function Svg:path(d, fill, line, extra, color)
    self:add(string.format('<path d="%s"%s%s/>', d, strokeAttr(fill, line, color), extra or ""))
end

function Svg:line(pts, color, width, extra)
    local d = {}
    for i, p in ipairs(pts) do d[#d + 1] = (i == 1 and "M" or "L") .. n(p[1]) .. " " .. n(p[2]) end
    self:path(table.concat(d, " "), "none", width, extra, color)
end

--- 一组只有描边、合在一起的形状（像手机上的 Pen.union）：先画所有描边，再盖上填色
function Svg:union(shapes, fill, line)
    for _, e in ipairs(shapes) do self:ellipse(e[1], e[2], e[3], e[4], fill, line) end
    for _, e in ipairs(shapes) do self:ellipse(e[1], e[2], e[3], e[4], fill, 0) end
end

function Svg:group(transform, fn)
    self:add('<g transform="' .. transform .. '">')
    fn()
    self:add("</g>")
end

function Svg:sparkle(x, y, r, fill)
    local k = r * 0.28
    self:path(string.format("M%s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %s Z",
        n(x), n(y - r), n(x + k), n(y - k), n(x + r), n(y), n(x + k), n(y + k), n(x), n(y + r),
        n(x - k), n(y + k), n(x - r), n(y), n(x - k), n(y - k), n(x), n(y - r)), fill or C.yellow, 2)
end

function Svg:heart(x, y, s, fill, line)
    self:path(string.format("M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z",
        n(x), n(y + s * 0.9),
        n(x - s * 1.4), n(y), n(x - s * 0.7), n(y - s * 1.1), n(x), n(y - s * 0.35),
        n(x + s * 0.7), n(y - s * 1.1), n(x + s * 1.4), n(y), n(x), n(y + s * 0.9)), fill, line or 2.4)
end

-- MARK: 零食（画在 0～20 的小格子里，中心 10,10）

local SNACK_DRAW = {
    cookie = function(g)
        g:ellipse(10, 10, 9, 8.4, C.tan, 2)
        for _, p in ipairs({ { 6, 8 }, { 13, 6.5 }, { 11, 13.5 }, { 7, 13 } }) do g:ellipse(p[1], p[2], 1.3, 1.3, C.patch, 0) end
    end,
    cake = function(g)
        g:path("M2 16 L18 16 L18 9 L2 12 Z", C.cream, 2)
        g:path("M2 12 L18 9 L18 11.5 L2 14.2 Z", C.pink, 0)
        g:ellipse(13, 6, 3, 3.2, C.rose, 1.8)
    end,
    pudding = function(g)
        g:path("M4 17 L16 17 L14 7 L6 7 Z", C.yellow, 2)
        g:path("M6 7 L14 7 L14.6 10 Q10 11.5 5.4 10 Z", C.patch, 0)
        g:ellipse(10, 18, 8, 1.6, "#ffffff", 1.6)
    end,
    candy = function(g)
        g:path("M2 6 L6 10 L2 14 Z", C.pink, 1.8)
        g:path("M18 6 L14 10 L18 14 Z", C.pink, 1.8)
        g:ellipse(10, 10, 5, 4.4, C.rose, 2)
    end,
    donut = function(g)
        g:ellipse(10, 10, 8.6, 7.6, C.tan, 2)
        g:ellipse(10, 9.4, 7.4, 6.2, C.pink, 0)
        g:ellipse(10, 10, 2.6, 2.2, "#ffffff", 1.8)
        for _, p in ipairs({ { 5, 7 }, { 14, 6 }, { 15, 12 }, { 6, 13 } }) do g:line({ p, { p[1] + 1.4, p[2] + 0.8 } }, C.blue, 1.4) end
    end,
    icecream = function(g)
        g:path("M5 9 L15 9 L10 19 Z", C.tan, 2)
        g:ellipse(10, 7, 5.6, 5, C.pink, 2)
    end,
    milk = function(g)
        g:path("M5 7 L10 3 L15 7 Z", "#ffffff", 1.8)
        g:rect(5, 7, 10, 11, 1.4, "#ffffff", 2)
        g:rect(6.5, 10, 7, 4, 1, C.blue, 0)
    end,
    onigiri = function(g)
        g:path("M10 2.5 Q12 2.5 17.5 14 Q18 17.5 14.5 17.5 L5.5 17.5 Q2 17.5 2.5 14 Q8 2.5 10 2.5 Z", "#ffffff", 2)
        g:rect(6.5, 12, 7, 5.5, 1, INK, 0)
    end,
}

local function drawSnack(g, id, x, y, size)
    local f = SNACK_DRAW[id] or SNACK_DRAW.cookie
    local s = size / 20
    g:group(string.format("translate(%s %s) scale(%s)", n(x - size / 2), n(y - size / 2), n(s)), function() f(g) end)
end

-- MARK: 云朵（照着手机版 PetPen 的小天使画，在 0～100 的格子里）

local function face(g, x, y, pose)
    local function blush()
        for _, dx in ipairs({ -14, 14 }) do g:ellipse(x + dx, y + 6, 4.6, 2.8, C.blush, 0, ' fill-opacity="0.55"') end
    end
    local function arcs(up)
        for _, dx in ipairs({ -8, 8 }) do
            g:path(string.format("M%s %s Q%s %s %s %s", n(x + dx - 4), n(y + 1), n(x + dx), n(up and y - 5 or y + 5), n(x + dx + 4), n(y + 1)), "none", 2.6)
        end
    end
    local function smile(yy)
        g:path(string.format("M%s %s Q%s %s %s %s", n(x - 4), n(yy), n(x), n(yy + 4), n(x + 4), n(yy)), "none", 2.4)
    end
    if pose == "happy" then
        arcs(true); blush(); smile(y + 7)
    elseif pose == "eating" then
        arcs(true); blush(); g:ellipse(x, y + 8, 3.4, 3.8, C.rose, 2)
    elseif pose == "sleeping" then
        arcs(false); blush(); g:line({ { x - 2, y + 8 }, { x + 2, y + 8 } }, INK, 2.2)
    else
        local yy = pose == "reading" and y + 3 or y
        for _, dx in ipairs({ -8, 8 }) do
            g:ellipse(x + dx, yy, 2.8, 3.2, INK, 0)
            g:ellipse(x + dx + 0.9, yy - 1.1, 0.9, 0.9, "#ffffff", 0)
        end
        for _, dx in ipairs({ -14, 14 }) do g:ellipse(x + dx, yy + 6, 4.6, 2.8, C.blush, 0, ' fill-opacity="0.55"') end
        smile(yy + 6)
    end
end

local function drawCloudy(g, pose, snack)
    -- 翅膀
    for _, w in ipairs({ { 22, -20 }, { 78, 20 } }) do
        local x, r = w[1], w[2]
        g:group(string.format("rotate(%s %s 52)", r, x), function()
            g:union({ { x, 48, 14, 10 }, { x + (x < 50 and -4 or 4), 58, 11, 8 } }, "#ffffff", 2.6)
        end)
    end
    for _, x in ipairs({ 24, 76 }) do g:ellipse(x, 70, 6, 5.5, "#ffffff", 3) end
    g:ellipse(50, 60, 29, 27, "#ffffff", 4)
    -- 头顶一小撮卷毛
    g:path("M46 34 Q44 24 54 28 Q60 32 52 36", "none", 4, nil, C.honey)
    -- 光环
    g:ellipse(50, 16, 15, 5, "none", 6)
    g:ellipse(50, 16, 15, 5, "none", 3, nil)
    g.out[#g.out] = g.out[#g.out]:gsub('stroke="' .. INK .. '"', 'stroke="' .. C.yellow .. '"')
    face(g, 50, 62, pose)
    -- 手里的东西
    if pose == "reading" then
        g:group("rotate(-4 50 84)", function()
            g:ellipse(39, 84, 12, 9, C.pink, 3)
            g:ellipse(61, 84, 12, 9, C.yellow, 3)
            for _, y in ipairs({ 81, 86 }) do
                g:line({ { 32, y }, { 44, y } }, INK, 1.4, ' stroke-opacity="0.6"')
                g:line({ { 56, y }, { 68, y } }, INK, 1.4, ' stroke-opacity="0.6"')
            end
        end)
        for _, x in ipairs({ 27, 73 }) do g:ellipse(x, 85, 5, 4.5, "#ffffff", 2.4) end
    elseif pose == "eating" then
        drawSnack(g, snack or "cookie", 72, 82, 22)
        g:ellipse(66, 88, 5, 4.5, "#ffffff", 2.4)
    elseif pose == "sleeping" then
        -- 睡觉的 z（NanoSVG 不能写字，用线画）
        for _, z in ipairs({ { 76, 28, 6 }, { 86, 16, 8 }, { 97, 2, 10 } }) do
            local x, y, s = z[1], z[2], z[3]
            g:line({ { x, y }, { x + s, y }, { x, y + s }, { x + s, y + s } }, INK, 2, ' stroke-opacity="0.75"')
        end
    end
end

-- MARK: 小屋里的东西（画布 600 × 440，墙 0～300，地板 300～440）

local function garlandPoint(t)
    -- 二次曲线 (0,18) → 控制点 (300,80) → (600,18)
    local u = 1 - t
    return u * u * 0 + 2 * u * t * 300 + t * t * 600, u * u * 18 + 2 * u * t * 80 + t * t * 18
end

local DRAW = {}

function DRAW.wallpaper(g)
    for row = 0, 4 do
        for col = 0, 10 do
            local x = col * 60 + (row % 2) * 30 + 15
            local y = row * 60 + 30
            if row % 2 == 0 then
                g:heart(x, y, 4, C.pink, 0)
            else
                g:ellipse(x, y, 3, 3, C.yellow, 0)
            end
        end
    end
end

function DRAW.floor(g)
    for i, y in ipairs({ 330, 365, 405 }) do
        g:line({ { 0, y }, { 600, y } }, C.wood, 2.4)
        local off = (i % 2) * 70
        for x = 60 + off, 560, 140 do
            g:line({ { x, y - (i == 1 and 30 or 35) + 2 }, { x, y - 2 } }, C.wood, 2)
        end
    end
end

function DRAW.garland(g)
    g:path("M0 18 Q300 80 600 18", "none", 2)
    local colors = { C.pink, C.yellow, C.mint, C.blue, C.lav }
    for i = 1, 11 do
        local t = i / 12
        local x, y = garlandPoint(t)
        g:path(string.format("M%s %s L%s %s L%s %s Z", n(x - 11), n(y), n(x + 11), n(y), n(x), n(y + 22)), colors[(i - 1) % 5 + 1], 2)
    end
end

function DRAW.moon(g)
    g:line({ { 185, 0 }, { 185, 44 } }, INK, 1.6)
    g:path("M196 50 A18 18 0 1 0 196 82 A14 14 0 1 1 196 50 Z", C.yellow, 2.4)
    g:line({ { 205, 66 }, { 205, 84 } }, INK, 1.2)
    g:sparkle(205, 90, 6)
end

function DRAW.painting(g, shabby)
    local function art()
        g:line({ { 100, 62 }, { 70, 80 } }, INK, 1.6)
        g:line({ { 100, 62 }, { 130, 80 } }, INK, 1.6)
        g:ellipse(100, 62, 2.4, 2.4, INK, 0)
        g:rect(58, 78, 84, 66, 4, C.yellow, 3)
        g:rect(67, 87, 66, 48, 2, C.mint, 2)
        g:path("M67 135 L88 108 L102 122 L112 112 L133 135 Z", C.green, 2)
        g:ellipse(118, 100, 6, 6, C.orange, 1.6)
    end
    if shabby >= 2 then g:group("rotate(-9 100 62)", art) else art() end
end

function DRAW.clock(g)
    g:ellipse(232, 98, 26, 26, "#ffffff", 3)
    g:ellipse(232, 98, 20, 20, "none", 1.4, ' stroke-dasharray="2 8.5"')
    g:line({ { 232, 98 }, { 232, 84 } }, INK, 2.6)
    g:line({ { 232, 98 }, { 242, 104 } }, INK, 2.6)
    g:ellipse(232, 98, 2.4, 2.4, C.rose, 0)
    g:ellipse(214, 74, 6, 6, C.pink, 2)
    g:ellipse(250, 74, 6, 6, C.pink, 2)
end

function DRAW.window(g, shabby, has)
    g:rect(330, 60, 120, 105, 8, C.blue, 3)
    if has.rainbow then
        for i, c in ipairs({ C.rose, C.orange, C.yellow, C.green, C.lav }) do
            local r = 46 - (i - 1) * 6
            g:path(string.format("M%s 158 A%s %s 0 0 1 %s 158", n(390 - r), n(r), n(r), n(390 + r)), "none", 5.4, nil, c)
        end
    end
    g:line({ { 390, 60 }, { 390, 165 } }, INK, 2.4)
    g:line({ { 330, 112 }, { 450, 112 } }, INK, 2.4)
    if not has.rainbow then
        g:ellipse(356, 84, 10, 6, "#ffffff", 0)
        g:ellipse(366, 82, 8, 6, "#ffffff", 0)
    end
    g:sparkle(422, 84, 7)
    if shabby >= 2 then
        g:line({ { 338, 68 }, { 352, 82 }, { 346, 90 }, { 362, 104 } }, INK, 1.6)
        g:line({ { 352, 82 }, { 362, 80 } }, INK, 1.2)
    end
    g:rect(322, 163, 136, 10, 3, "#ffffff", 2.6)
end

function DRAW.curtains(g)
    g:path("M324 50 Q346 110 328 178 L352 178 Q360 110 352 50 Z", C.pink, 2.6)
    g:path("M456 50 Q434 110 452 178 L428 178 Q420 110 428 50 Z", C.pink, 2.6)
    for _, x in ipairs({ 340, 440 }) do g:ellipse(x, 128, 6, 4, C.yellow, 2) end
    g:line({ { 314, 50 }, { 466, 50 } }, C.brown, 4)
    g:ellipse(314, 50, 4, 4, C.brown, 0)
    g:ellipse(466, 50, 4, 4, C.brown, 0)
end

function DRAW.shelf(g, _, has)
    g:rect(478, 132, 104, 210, 6, C.wood, 3)
    g:rect(486, 140, 88, 194, 3, "#f5d3b3", 0)
    for _, y in ipairs({ 200, 268 }) do g:line({ { 482, y }, { 578, y } }, INK, 3) end
    local colors = { C.pink, C.blue, C.yellow, C.mint, C.lav, C.rose, C.orange }
    local x = 490
    for i = 1, 6 do
        local w = 10 + (i * 7) % 5
        local h = 36 + (i * 5) % 18
        g:rect(x, 198 - h, w, h, 2, colors[i], 2)
        x = x + w + 2
    end
    x = 492
    for i = 1, 5 do
        local w = 12 + (i * 3) % 5
        local h = 40 + (i * 9) % 16
        if i == 5 then
            g:group(string.format("rotate(18 %s 266)", n(x)), function() g:rect(x, 266 - h, w, h, 2, colors[(i + 2) % 7 + 1], 2) end)
        else
            g:rect(x, 266 - h, w, h, 2, colors[(i + 2) % 7 + 1], 2)
        end
        x = x + w + 3
    end
    g:heart(528, 312, 9, C.pink, 2)
    g:ellipse(556, 318, 10, 12, C.lav, 2)
    if not has.plant and not has.trophy then g:sparkle(530, 120, 7) end
end

function DRAW.plant(g, shabby)
    g:path("M494 112 L522 112 L518 132 L498 132 Z", C.orange, 2.4)
    if shabby >= 2 then
        g:path("M508 112 Q500 96 490 104", "none", 3, nil, C.green)
        g:path("M508 112 Q516 98 528 106", "none", 3, nil, C.green)
        g:ellipse(490, 106, 7, 4, C.green, 2)
        g:ellipse(528, 108, 7, 4, C.green, 2)
        -- 掉在地上的一片叶子
        g:ellipse(540, 400, 8, 4, C.green, 2, ' transform="rotate(20 540 400)"')
    else
        g:path("M508 112 Q506 92 508 80", "none", 3, nil, C.green)
        g:ellipse(498, 94, 10, 5, C.green, 2, ' transform="rotate(-35 498 94)"')
        g:ellipse(519, 90, 10, 5, C.green, 2, ' transform="rotate(35 519 90)"')
        g:ellipse(508, 76, 5, 8, C.green, 2)
    end
end

function DRAW.trophy(g)
    g:path("M542 96 L570 96 Q570 116 556 118 Q542 116 542 96 Z", C.yellow, 2.4)
    g:path("M542 100 Q532 100 534 108 Q536 114 544 112", "none", 2)
    g:path("M570 100 Q580 100 578 108 Q576 114 568 112", "none", 2)
    g:rect(552, 118, 8, 6, 1, C.yellow, 2)
    g:rect(546, 124, 20, 8, 2, C.wood, 2)
    g:sparkle(578, 88, 5)
end

function DRAW.rug(g)
    g:ellipse(300, 386, 172, 36, C.pink, 3)
    g:ellipse(300, 386, 142, 26, "none", 3, ' stroke-dasharray="7 7"')
    g.out[#g.out] = g.out[#g.out]:gsub('stroke="' .. INK .. '"', 'stroke="#ffffff"')
end

function DRAW.bed(g)
    g:rect(22, 214, 28, 128, 10, C.wood, 3)
    g:heart(36, 238, 7, C.pink, 2)
    g:rect(160, 256, 16, 86, 6, C.wood, 3)
    g:rect(44, 282, 124, 38, 10, "#ffffff", 3)
    g:path("M80 276 Q124 268 170 276 L170 322 L80 322 Z", C.pink, 3)
    for _, x in ipairs({ 100, 124, 148 }) do g:ellipse(x, 298, 3.4, 3.4, "#ffffff", 0) end
    g:ellipse(66, 272, 22, 11, "#ffffff", 3)
    g:rect(52, 320, 8, 20, 3, C.wood, 2.4)
end

function DRAW.balloons(g)
    for _, b in ipairs({ { 160, 176, C.pink }, { 196, 160, C.rose }, { 178, 132, C.yellow } }) do
        g:path(string.format("M%s %s Q%s %s 170 258", n(b[1]), n(b[2] + 16), n(b[1] - 6), n(b[2] + 60)), "none", 1.4)
        g:heart(b[1], b[2], 13, b[3], 2.4)
    end
end

function DRAW.table(g)
    g:rect(405, 272, 10, 62, 3, C.wood, 2.6)
    g:ellipse(410, 336, 26, 6, C.wood, 2.6)
    g:ellipse(410, 268, 50, 10, C.tan, 3)
end

function DRAW.lamp(g, shabby)
    if shabby == 0 then
        for _, a in ipairs({ { 404, 212, 396, 204 }, { 430, 196, 430, 186 }, { 456, 212, 464, 204 } }) do
            g:line({ { a[1], a[2] }, { a[3], a[4] } }, C.orange, 2.4)
        end
    end
    g:line({ { 430, 262 }, { 430, 228 } }, INK, 3)
    g:ellipse(430, 262, 12, 4, C.wood, 2.4)
    g:path("M412 232 L448 232 L440 206 L420 206 Z", shabby == 0 and C.yellow or C.gray, 2.6)
end

function DRAW.teacup(g)
    if true then
        g:path("M382 256 Q378 248 384 244", "none", 1.6, ' stroke-opacity="0.6"')
        g:path("M392 254 Q388 246 394 240", "none", 1.6, ' stroke-opacity="0.6"')
    end
    g:path("M376 252 L398 252 L396 262 Q387 268 378 262 Z", "#ffffff", 2.4)
    g:path("M398 254 Q405 254 403 259 Q401 262 397 261", "none", 2)
    g:heart(387, 258, 2.6, C.pink, 0)
end

function DRAW.books(g)
    g:rect(184, 350, 54, 12, 3, C.blue, 2.4)
    g:rect(190, 338, 46, 12, 3, C.yellow, 2.4)
    g:rect(186, 326, 50, 12, 3, C.pink, 2.4)
    g:rect(194, 316, 34, 10, 3, C.mint, 2.2)
end

function DRAW.cushion(g)
    g:heart(428, 372, 17, C.rose, 3)
    g:path("M420 366 Q428 372 436 366", "none", 1.6)
end

function DRAW.chandelier(g)
    g:line({ { 300, 0 }, { 300, 34 } }, INK, 2)
    g:path("M262 44 Q300 64 338 44", "none", 3)
    for _, x in ipairs({ 262, 300, 338 }) do
        g:rect(x - 4, 26, 8, 18, 2, "#ffffff", 2)
        g:path(string.format("M%s 26 Q%s 16 %s 18 Q%s 22 %s 26 Z", n(x), n(x - 3), n(x), n(x + 4), n(x)), C.yellow, 1.6)
    end
    for _, d in ipairs({ { 274, 56 }, { 300, 62 }, { 326, 56 } }) do
        g:line({ { d[1], d[2] - 8 }, { d[1], d[2] } }, INK, 1.2)
        g:path(string.format("M%s %s L%s %s L%s %s L%s %s Z", n(d[1]), n(d[2]), n(d[1] + 4), n(d[2] + 6), n(d[1]), n(d[2] + 13), n(d[1] - 4), n(d[2] + 6)), C.lav, 1.6)
    end
end

-- 落灰：角落蜘蛛网、地上几团灰
local function dust(g, level)
    g:path("M0 0 L0 60", "none", 1.4, ' stroke-opacity="0.6"', C.dust)
    for _, r in ipairs({ 18, 34, 52 }) do
        g:path(string.format("M0 %s Q%s %s %s 0", n(r * 1.1), n(r * 0.45), n(r * 0.45), n(r * 1.1)), "none", 1.4, ' stroke-opacity="0.7"', C.dust)
    end
    g:line({ { 0, 0 }, { 50, 50 } }, C.dust, 1.4, ' stroke-opacity="0.7"')
    g:line({ { 0, 0 }, { 60, 22 } }, C.dust, 1.4, ' stroke-opacity="0.7"')
    g:line({ { 0, 0 }, { 22, 60 } }, C.dust, 1.4, ' stroke-opacity="0.7"')
    local spots = { { 96, 404 }, { 482, 414 }, { 262, 424 } }
    if level >= 2 then
        table.insert(spots, { 560, 362 })
        table.insert(spots, { 30, 380 })
    end
    for _, p in ipairs(spots) do
        local x, y = p[1], p[2]
        g:path(string.format("M%s %s q4 -8 9 -3 q5 -7 9 1 q6 0 3 6 q-10 4 -21 0 q-4 -3 0 -4 z", n(x - 10), n(y + 3)), C.gray, 2, nil, C.dust)
        g:line({ { x - 4, y - 1 }, { x + 1, y - 4 } }, C.dust, 1.2)
    end
end

-- 旧旧的：墙纸翘起来一块、地板裂缝
local function wornOut(g)
    g:path("M246 176 L276 170 L282 196 L268 214 L244 206 Z", "#efe2d0", 2, nil, C.dust)
    g:path("M276 170 L282 196 L296 184 Z", "#ffffff", 2, nil, C.dust)
    g:line({ { 120, 372 }, { 136, 380 }, { 132, 390 }, { 150, 398 } }, C.dust, 2)
    g:line({ { 520, 300 }, { 530, 312 }, { 526, 322 } }, C.dust, 2)
end

--- 整个小屋的 SVG。pose：云朵的样子；snack：吃东西时手里拿的零食
function Pet.roomSvg(s, pose, snack)
    local g = newSvg()
    local has = s.owned or {}
    local shabby = Pet.shabby(s)
    g:add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 440" width="600" height="440">')
    g:rect(0, 0, 600, 300, 0, C.wall, 0)
    g:rect(0, 300, 600, 140, 0, C.floor, 0)
    if has.wallpaper then DRAW.wallpaper(g) end
    if has.floor then DRAW.floor(g) end
    g:line({ { 0, 300 }, { 600, 300 } }, INK, 3)
    -- 墙上
    DRAW.window(g, shabby, has)
    for _, id in ipairs({ "curtains", "painting", "clock", "garland", "moon", "chandelier" }) do
        if has[id] then DRAW[id](g, shabby, has) end
    end
    if shabby >= 2 then wornOut(g) end
    -- 靠墙的大家具
    for _, id in ipairs({ "shelf", "plant", "trophy", "bed", "balloons", "rug", "table", "lamp", "teacup" }) do
        if has[id] then DRAW[id](g, shabby, has) end
    end
    -- 云朵坐在中间
    g:ellipse(300, 352, 52, 8, INK, 0, ' fill-opacity="0.12"')
    g:group("translate(235 222) scale(1.3)", function() drawCloudy(g, pose or "normal", snack) end)
    -- 前面的小东西
    for _, id in ipairs({ "books", "cushion" }) do
        if has[id] then DRAW[id](g, shabby, has) end
    end
    if shabby >= 1 then dust(g, shabby) end
    g:rect(1.5, 1.5, 597, 437, 18, "none", 3)
    g:add("</svg>")
    return table.concat(g.out, "\n")
end

-- MARK: 小屋界面

local POKES = { "今天看到哪一章啦？", "我在等你翻下一页～", "摸摸头，嘿嘿", "读累了就歇一会儿吧", "书里的人物好有趣！", "小屋越来越像家啦" }

function Pet.line(s)
    local shabby = Pet.shabby(s)
    if shabby >= 2 then
        return L("好久不见呀～屋子变得旧旧的，我在打瞌睡等你。没关系，哪天读够 %d 字，我们就一起把家收拾好！", Pet.CLEAN_CHARS)
    elseif shabby == 1 then
        return L("屋子落了一点点灰～哪天读够 %d 字，就能打扫干净啦", Pet.CLEAN_CHARS)
    end
    if #s.gifts > 0 then return L("有 %d 个礼物盒还没拆！", #s.gifts) end
    local today = Pet.today(s)
    if s.fed_day == dayKey() and s.fed_snack then
        local it = find(Pet.SNACKS, s.fed_snack)
        return L("今天吃到%s啦，好幸福～", it and L(it.name) or "")
    end
    if today > 0 then return L("今天陪你读了 %d 字", today) end
    if Pet.ownedCount(s) == 0 then return L("这里还空空的～一起读书，就能给小屋添家具哦") end
    return L("在等你一起看书～")
end

function Pet.pose(s)
    if Pet.shabby(s) >= 2 then return "sleeping" end
    if s.fed_day == dayKey() then return "happy" end
    if Pet.today(s) > 0 then return "reading" end
    return "normal"
end

local PetHome = InputContainer:extend{
    pose = nil,       -- 临时的样子（吃东西、被摸头）
    snack = nil,
    bubble = nil,     -- 临时的话
}

local svg_counter = 0

function PetHome:init()
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events.TapRoom = {
        GestureRange:new{ ges = "tap", range = function() return self.room_box and self.room_box.dimen or Geom:new{} end },
    }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self:build()
end

function PetHome:writeSvg(s)
    local dir = DataStorage:getDataDir() .. "/cache"
    svg_counter = svg_counter + 1
    local file = string.format("%s/readingbuddy-room-%d.svg", dir, svg_counter % 2)
    local f = io.open(file, "w")
    if not f then return end
    f:write(Pet.roomSvg(s, self.pose or Pet.pose(s), self.snack))
    f:close()
    return file
end

function PetHome:build()
    local s = Pet.state()
    local pad = Screen:scaleBySize(14)
    local inner_w = self.width - 2 * pad
    if self.room then self.room:free() end
    local title = TitleBar:new{
        width = self.width,
        fullscreen = true,
        title = L("云朵的小屋"),
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local room_w = inner_w
    local room_h = math.floor(room_w * 440 / 600)
    -- 屏幕比较扁的时候缩小一点，给下面的按钮留地方
    local max_h = math.floor(self.height * 0.5)
    if room_h > max_h then
        room_h = max_h
        room_w = math.floor(room_h * 600 / 440)
    end
    self.room = ImageWidget:new{
        file = self:writeSvg(s),
        width = room_w,
        height = room_h,
        file_do_cache = false,
        original_in_nightmode = true,
    }
    self.room_box = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = room_h }, self.room }

    local face = Font:getFace("cfont", 20)
    local small = Font:getFace("cfont", 16)
    local bubble = FrameContainer:new{
        bordersize = Size.border.thin,
        radius = Screen:scaleBySize(16),
        padding = Screen:scaleBySize(8),
        padding_left = Screen:scaleBySize(14),
        padding_right = Screen:scaleBySize(14),
        TextBoxWidget:new{ text = self.bubble or Pet.line(s), face = face, width = inner_w - Screen:scaleBySize(40), alignment = "center" },
    }

    local today = Pet.today(s)
    local names = { L("零食"), L("一件家具"), L("一件家具"), L("一件稀有摆饰") }
    local progress_text
    local next_i
    for i, t in ipairs(Pet.TIERS) do
        if today < t then next_i = i; break end
    end
    if next_i then
        progress_text = L("今天读了 %d 字 · 再读 %d 字得%s", today, Pet.TIERS[next_i] - today, names[next_i])
    else
        progress_text = L("今天读了 %d 字 · 今天的礼物都拿到啦！", today)
    end
    local last = Pet.TIERS[#Pet.TIERS]
    local bar = ProgressWidget:new{
        width = inner_w,
        height = Screen:scaleBySize(14),
        percentage = math.min(1, today / last),
        ticks = { Pet.TIERS[1], Pet.TIERS[2], Pet.TIERS[3] },
        last = last,
    }
    local owned = Pet.ownedCount(s)
    local all = #Pet.ITEMS + #Pet.RARE
    local info = TextBoxWidget:new{
        text = L("家具摆饰 %d / %d 件 · 零食 %d 份", owned, all, Pet.snackCount(s)),
        face = small, width = inner_w, alignment = "center",
    }

    local gifts = #s.gifts
    local buttons = ButtonTable:new{
        width = inner_w,
        buttons = {
            {
                { text = gifts > 0 and L("拆礼物（%d）", gifts) or L("拆礼物"), enabled = gifts > 0, callback = function() self:openGift() end },
                { text = L("投喂零食"), enabled = Pet.snackCount(s) > 0, callback = function() self:chooseSnack() end },
            },
            {
                { text = L("我的东西"), callback = function() self:showThings() end },
                { text = L("规则"), callback = function() self:showRules() end },
            },
        },
        show_parent = self,
    }

    local gap = VerticalSpan:new{ width = Screen:scaleBySize(10) }
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            title,
            gap,
            self.room_box,
            gap,
            bubble,
            gap,
            TextBoxWidget:new{ text = progress_text, face = small, width = inner_w, alignment = "center" },
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            bar,
            VerticalSpan:new{ width = Screen:scaleBySize(4) },
            info,
            gap,
            buttons,
        },
    }
end

function PetHome:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function PetHome:onTapRoom()
    if self.pose == "eating" then return true end
    local s = Pet.state()
    if Pet.shabby(s) >= 2 then
        self.pose = "happy"
        self.bubble = L("唔……你来啦！")
    else
        self.pose = "happy"
        self.bubble = L(POKES[math.random(#POKES)])
    end
    self:refresh()
    UIManager:scheduleIn(3, function()
        if self.closed then return end
        self.pose, self.bubble = nil, nil
        self:refresh()
    end)
    return true
end

function PetHome:openGift()
    local g = Pet.openGift()
    if not g then return end
    local name = Pet.thingName(g)
    if g.t == "snack" then
        self.bubble = L("哇，是%s！先收进零食柜，饿了就喂我吧～", name)
    else
        self.bubble = L("是%s！已经摆进小屋里啦", name)
    end
    self.pose = "happy"
    self:refresh()
end

function PetHome:chooseSnack()
    local s = Pet.state()
    local rows = {}
    local dialog
    for _, it in ipairs(Pet.SNACKS) do
        local c = s.snacks[it.id] or 0
        if c > 0 then
            table.insert(rows, { {
                text = L("%s × %d", L(it.name), c),
                callback = function()
                    UIManager:close(dialog)
                    self:feed(it.id)
                end,
            } })
        end
    end
    table.insert(rows, { { text = L("取消"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{ title = L("喂云朵吃什么？"), buttons = rows }
    UIManager:show(dialog)
end

function PetHome:feed(id)
    if not Pet.feed(id) then return end
    self.pose, self.snack = "eating", id
    self.bubble = L("好好吃！谢谢你～")
    self:refresh()
    UIManager:scheduleIn(3, function()
        if self.closed then return end
        self.pose, self.snack, self.bubble = nil, nil, nil
        self:refresh()
    end)
end

function PetHome:showThings()
    local s = Pet.state()
    local sep = L("、")
    local lines = {}
    local function section(title, list)
        local have = {}
        for _, it in ipairs(list) do
            if s.owned[it.id] then table.insert(have, L(it.name)) end
        end
        table.insert(lines, L("%s（%d / %d）", title, #have, #list))
        table.insert(lines, #have > 0 and table.concat(have, sep) or L("（还没有）"))
        table.insert(lines, "")
    end
    section(L("家具摆饰"), Pet.ITEMS)
    section(L("稀有摆饰"), Pet.RARE)
    local snacks = {}
    for _, it in ipairs(Pet.SNACKS) do
        local c = s.snacks[it.id] or 0
        if c > 0 then table.insert(snacks, L("%s × %d", L(it.name), c)) end
    end
    table.insert(lines, L("零食柜"))
    table.insert(lines, #snacks > 0 and table.concat(snacks, sep) or L("（空的）"))
    table.insert(lines, "")
    table.insert(lines, L("一共喂过云朵 %d 次", s.fed_count))
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), alignment = "left" })
end

function PetHome:showRules()
    UIManager:show(InfoMessage:new{
        text = L("每天所有书加起来，真正往前读过的字才算（翻得太快、从目录跳着翻的不算）。\n\n· 读到 2000 字：一份零食\n· 读到 5000 字：一件家具摆饰\n· 读到 1 万字：再一件家具摆饰\n· 读到 2 万字：一件稀有摆饰\n\n礼物会变成礼物盒，到小屋里拆开。家具会自己摆进屋里，读得越多，家里越丰富。\n\n好几天没读书，屋子会落灰、变得旧旧的，不过东西一件都不会少。哪天读够 1000 字，就能打扫干净。"),
    })
end

function PetHome:onClose()
    self.closed = true
    if self.room then self.room:free() end
    UIManager:close(self, "full")
    return true
end

function PetHome:onShow()
    UIManager:setDirty(self, "full")
end

function Pet.showHome()
    UIManager:show(PetHome:new{})
end

return Pet
