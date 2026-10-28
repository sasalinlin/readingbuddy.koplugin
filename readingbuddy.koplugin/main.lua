--[[--
Reading Buddy：AI 陪读朋友。只看得到你已经读到的位置为止的内容，绝不剧透。

从 iPhone App「一起看书啦」（ReadBuddy）搬过来的：
- 划线后可以「吐槽这句」「问一问」，也可以在阅读菜单里打开聊天；
- 发给 AI 的上下文只到「读到的最远位置」为止：前面整段用摘要（缓存在这本书的 sidecar 里），
  最后 3000～13000 字给原文；
- 任意服务商、任意模型：Anthropic 用 Messages API，其他走 OpenAI 兼容接口。

@module koplugin.ReadingBuddy
--]]--

local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local Screen = Device.screen

local I18n = require("rb_i18n")
local L = I18n.L

-- MARK: - 陪读朋友的性格（照抄 App 的 Persona）

local PERSONAS = {
    { id = "snark", name = "毒舌搭子", tagline = "嘴毒心软，陪你一起骂角色",
      prompt = "你是嘴巴很毒、但其实很投入的追书搭子。吐槽犀利好笑，敢损角色、损作者的套路，会跟主人一起拍桌子、翻白眼；但不刻薄主人本人，主人难过时也会收起毒舌安慰两句。" },
    { id = "gentle", name = "温柔解答", tagline = "耐心细致，有问必答",
      prompt = "你是温柔耐心的读书伙伴。会认真接住主人的情绪，把看不懂的地方（人物关系、前因后果、生僻词和典故）讲清楚，语气软软的，偶尔夸夸主人读得仔细。" },
    { id = "scholar", name = "考据党", tagline = "细节控，伏笔雷达",
      prompt = "你是热爱考据的细节控。喜欢翻前文找呼应和伏笔、对时间线、数人物出场，会引用原文当证据，也会解释书里涉及的历史、文化和专业知识。说话严谨但不无聊，发现细节时会很兴奋。" },
}
local CUSTOM_ID = "custom"

-- MARK: - 服务商（照抄 App 的 AIProvider.all）

local PROVIDERS = {
    { id = "anthropic", name = "Claude（Anthropic）", proto = "anthropic", base = "https://api.anthropic.com",
      models = { "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5" }, signup = "console.anthropic.com" },
    { id = "openai", name = "ChatGPT（OpenAI）", proto = "openai", base = "https://api.openai.com/v1",
      models = { "gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o" }, signup = "platform.openai.com" },
    { id = "gemini", name = "Gemini（Google）", proto = "openai", base = "https://generativelanguage.googleapis.com/v1beta/openai",
      models = { "gemini-2.5-pro", "gemini-2.5-flash" }, signup = "aistudio.google.com" },
    { id = "deepseek", name = "DeepSeek", proto = "openai", base = "https://api.deepseek.com/v1",
      models = { "deepseek-chat", "deepseek-reasoner" }, signup = "platform.deepseek.com" },
    { id = "qwen", name = "通义千问（阿里云百炼）", proto = "openai", base = "https://dashscope.aliyuncs.com/compatible-mode/v1",
      models = { "qwen-max", "qwen-plus", "qwen-turbo", "qwen-long" }, signup = "bailian.console.aliyun.com" },
    { id = "kimi", name = "Kimi（月之暗面）", proto = "openai", base = "https://api.moonshot.cn/v1",
      models = { "kimi-latest", "moonshot-v1-128k", "moonshot-v1-32k" }, signup = "platform.moonshot.cn" },
    { id = "zhipu", name = "智谱 GLM", proto = "openai", base = "https://open.bigmodel.cn/api/paas/v4",
      models = { "glm-4.5", "glm-4-plus", "glm-4-flash" }, signup = "open.bigmodel.cn" },
    { id = "doubao", name = "豆包（火山方舟）", proto = "openai", base = "https://ark.cn-beijing.volces.com/api/v3",
      models = {}, signup = "console.volcengine.com/ark", note = "模型名填火山方舟控制台里的模型 ID 或接入点 ID。" },
    { id = "openrouter", name = "OpenRouter（多家模型聚合）", proto = "openai", base = "https://openrouter.ai/api/v1",
      models = {}, signup = "openrouter.ai", note = "点「获取模型列表」可以选几百个模型。" },
    { id = "custom", name = "其他（兼容 OpenAI 格式的接口）", proto = "openai", base = "",
      models = {}, signup = "", note = "填写服务商提供的接口地址（一般以 /v1 结尾）和模型名。大多数国内外服务商都兼容这种格式，也可以连同一个 Wi-Fi 下电脑上的本地模型（比如 Ollama）。" },
}

-- MARK: - 设置：全局的存在 G_reader_settings["readingbuddy"]（settings.reader.lua）

local Config = {}

function Config.all()
    return G_reader_settings:readSetting("readingbuddy") or {}
end

function Config.get(k, default)
    local v = Config.all()[k]
    if v == nil then return default end
    return v
end

function Config.set(k, v)
    local t = Config.all()
    t[k] = v
    G_reader_settings:saveSetting("readingbuddy", t)
    G_reader_settings:flush()
end

--- 按服务商分开存的值（model / base / key）
function Config.getFor(kind, pid)
    local t = Config.get(kind, {})
    return t[pid]
end

function Config.setFor(kind, pid, v)
    local t = Config.get(kind, {})
    t[pid] = v
    Config.set(kind, t)
end

function Config.provider()
    local id = Config.get("provider", "anthropic")
    for _, p in ipairs(PROVIDERS) do
        if p.id == id then return p end
    end
    return PROVIDERS[1]
end

function Config.model(p)
    local m = Config.getFor("models", p.id)
    if m and m ~= "" then return m end
    return p.models[1] or ""
end

function Config.baseURL(p)
    local b = Config.getFor("bases", p.id)
    if b and b ~= "" then return b end
    return p.base
end

function Config.key(p)
    return Config.getFor("keys", p.id) or ""
end

function Config.persona()
    local id = Config.get("persona", "snark")
    if id == CUSTOM_ID then
        local name = Config.get("custom_name", "")
        local desc = Config.get("custom_desc", "")
        return {
            id = CUSTOM_ID,
            display = name ~= "" and name or L("我的书友"),
            tagline = desc ~= "" and desc or L("自己写性格"),
            prompt = desc ~= "" and desc or "你是一个热情的读书伙伴。",
        }
    end
    for _, p in ipairs(PERSONAS) do
        if p.id == id then
            return { id = p.id, display = L(p.name), tagline = L(p.tagline), prompt = p.prompt }
        end
    end
    local p = PERSONAS[1]
    return { id = p.id, display = L(p.name), tagline = L(p.tagline), prompt = p.prompt }
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- MARK: - AI 接口（照 App 的 AIService）

local AI = {}

local function aiError(code, msg)
    if code == 401 or code == 403 then return L("API Key 无效或没有权限，请检查设置。") end
    if code == 404 then return L("找不到这个模型或接口地址，请检查设置里的模型名和地址。（%s）", msg or "") end
    if code == 429 then return L("请求太频繁或额度不足，请稍后再试。") end
    return L("AI 服务出错（%s）：%s", tostring(code), msg or "")
end

local function endpoint(base, path)
    local b = trim(base):gsub("/+$", "")
    if not b:match("^https?://") then return nil end
    return b .. path
end

--- 发 HTTP 请求，返回解析好的 JSON；出错时返回 nil, 错误说明
local function request(method, url, headers, body)
    headers = headers or {}
    if body then headers["Content-Length"] = tostring(#body) end
    -- 服务器让我们换个地址（301/302/307/308）时，带着同样的内容跟过去，最多跟 3 次
    for _ = 1, 4 do
        local sink = {}
        local req = { url = url, method = method, headers = headers, sink = ltn12.sink.table(sink), redirect = false }
        if body then req.source = ltn12.source.string(body) end
        -- https 直接用加密模块，老版本 KOReader 的 socket.http 不一定认 https
        local client = url:match("^https://") and https or http
        -- AI 回答可能要一两分钟
        socketutil:set_timeout(60, 240)
        local ok, code, resp_headers, status = pcall(function()
            return socket.skip(1, client.request(req))
        end)
        socketutil:reset_timeout()
        if not ok then
            return nil, L("连不上 AI 服务：%s", tostring(code))
        end
        if resp_headers == nil then
            return nil, L("连不上 AI 服务：%s", tostring(status or code))
        end
        local location = resp_headers.location or resp_headers.Location
        if (code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and location then
            if location:match("^/") then
                location = url:match("^(https?://[^/]+)") .. location
            end
            logger.info("ReadingBuddy: redirected", code, url, "->", location)
            if location == url then
                return nil, aiError(code, location)
            end
            url = location
        else
            local content = table.concat(sink)
            local okj, json = pcall(JSON.decode, content)
            if not okj or type(json) ~= "table" then json = {} end
            if type(code) ~= "number" or code < 200 or code >= 300 then
                local err = json.error
                local msg = (type(err) == "table" and err.message) or (type(err) == "string" and err) or content:sub(1, 300)
                if location then msg = msg .. " → " .. location end
                return nil, aiError(code, msg)
            end
            return json
        end
    end
    return nil, aiError(310, url)
end

--- 发给 AI。messages = { {role="user"/"assistant", text=...}, ... }
function AI.send(system, messages, max_tokens)
    local p = Config.provider()
    local key, model, base = Config.key(p), Config.model(p), Config.baseURL(p)
    if key == "" or model == "" or base == "" then
        return nil, L("还没设置 AI：请到「Reading Buddy › AI 设置」里选择服务商、填写 API Key 和模型。")
    end
    max_tokens = max_tokens or 8000
    if p.proto == "anthropic" then
        local url = endpoint(base, "/v1/messages")
        if not url then return nil, L("接口地址格式不对") end
        local msgs = {}
        for _, m in ipairs(messages) do table.insert(msgs, { role = m.role, content = m.text }) end
        local body = { model = model, max_tokens = max_tokens, system = system, messages = msgs }
        local headers = {
            ["content-type"] = "application/json",
            ["x-api-key"] = key,
            ["anthropic-version"] = "2026-10-21",
        }
        -- 新一代模型：设置思考力度；支持的模型开启拒答时自动换模型兜底
        local effort = { ["claude-opus-5-5"] = true, ["claude-opus-5"] = true, ["claude-sonnet-5-5"] = true,
                         ["claude-haiku-5-5"] = true, ["claude-fable-5-1"] = true }
        local fallback = { ["claude-opus-5-5"] = true, ["claude-opus-5"] = true, ["claude-sonnet-5-5"] = true,
                           ["claude-fable-5-1"] = true }
        if effort[model] then body.output_config = { effort = "medium" } end
        if fallback[model] then
            body.fallbacks = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        end
        local json, err = request("POST", url, headers, JSON.encode(body))
        if not json then return nil, err end
        if json.stop_reason == "refusal" then return nil, L("AI 没有回答这个问题，换个说法再试试。") end
        local parts = {}
        for _, c in ipairs(type(json.content) == "table" and json.content or {}) do
            if c.type == "text" and type(c.text) == "string" then table.insert(parts, c.text) end
        end
        local text = trim(table.concat(parts))
        if text == "" then return nil, L("AI 没有返回内容，请重试。") end
        return text
    else
        local url = endpoint(base, "/chat/completions")
        if not url then return nil, L("接口地址格式不对") end
        local msgs = { { role = "system", content = system } }
        for _, m in ipairs(messages) do table.insert(msgs, { role = m.role, content = m.text }) end
        local body = { model = model, messages = msgs, stream = false }
        local headers = {
            ["content-type"] = "application/json",
            ["Authorization"] = "Bearer " .. key,
        }
        local json, err = request("POST", url, headers, JSON.encode(body))
        if not json then return nil, err end
        local choice = type(json.choices) == "table" and json.choices[1] or nil
        if choice and choice.finish_reason == "content_filter" then
            return nil, L("AI 没有回答这个问题，换个说法再试试。")
        end
        local message = choice and choice.message or {}
        local text = ""
        if type(message.content) == "string" then
            text = message.content
        elseif type(message.content) == "table" then
            local parts = {}
            for _, c in ipairs(message.content) do
                if type(c.text) == "string" then table.insert(parts, c.text) end
            end
            text = table.concat(parts)
        end
        text = trim(text)
        if text == "" then return nil, L("AI 没有返回内容，请重试。") end
        return text
    end
end

--- 读取服务商提供的模型列表
function AI.fetchModels(p)
    local key, base = Config.key(p), Config.baseURL(p)
    local url = endpoint(base, p.proto == "anthropic" and "/v1/models?limit=100" or "/models")
    if not url then return nil, L("接口地址格式不对") end
    local headers = {}
    if p.proto == "anthropic" then
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2026-10-21"
    else
        headers["Authorization"] = "Bearer " .. key
    end
    local json, err = request("GET", url, headers)
    if not json then return nil, err end
    local ids = {}
    for _, m in ipairs(type(json.data) == "table" and json.data or {}) do
        if type(m.id) == "string" then table.insert(ids, m.id) end
    end
    table.sort(ids)
    return ids
end

-- MARK: - 文字工具（全部按 UTF-8 处理，「字」= 一个 UTF-8 字符）

--- byte 是不是一个字的开头
local function isLead(b)
    return b < 0x80 or b >= 0xC0
end

--- 每 step 个字记一个起点（字节位置，从 1 开始）。返回 starts、总字数
--- starts[k] = 第 k*step 个字的字节位置（k 从 0 开始）
local function charMarks(s, step)
    local starts = { [0] = 1 }
    local n = 0
    local byte = string.byte
    for i = 1, #s do
        if isLead(byte(s, i)) then
            if n > 0 and n % step == 0 then starts[n / step] = i end
            n = n + 1
        end
    end
    if n > 0 and n % step == 0 then starts[n / step] = #s + 1 end
    return starts, n
end

--- 从字节位置 i 往前/往后挪 n 个字
local function moveChars(s, i, n)
    local byte = string.byte
    if n < 0 then
        local left = -n
        while i > 1 and left > 0 do
            i = i - 1
            while i > 1 and not isLead(byte(s, i)) do i = i - 1 end
            left = left - 1
        end
    else
        local left = n
        while i <= #s and left > 0 do
            i = i + 1
            while i <= #s and not isLead(byte(s, i)) do i = i + 1 end
            left = left - 1
        end
    end
    return i
end

local function utf8len(s)
    local _, cont = s:gsub("[\128-\191]", "")
    return #s - cont
end

--- 拆成一个个 UTF-8 字
local function chars(s)
    local out = {}
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(out, c) end
    return out
end

local NUMERALS, CHAPTER_UNITS = {}, {}
for _, c in ipairs(chars("零一二三四五六七八九十百千万两〇0123456789０１２３４５６７８９")) do NUMERALS[c] = true end
for _, c in ipairs(chars("章回卷节集部篇")) do CHAPTER_UNITS[c] = true end
local CHAPTER_WORDS = { "序章", "序言", "楔子", "引子", "番外", "尾声", "后记" }

--- 这一行是不是章节名（照 App 导入 txt 时的规则）
local function isChapterLine(line)
    local t = line:gsub("^[%s　]+", ""):gsub("[%s　]+$", "")
    if t == "" or utf8len(t) > 30 then return false end
    if t:match("^[Cc][Hh][Aa][Pp][Tt][Ee][Rr]%s*%d+") then return true end
    for _, w in ipairs(CHAPTER_WORDS) do
        if t:sub(1, #w) == w then return true end
    end
    local cs = chars(t)
    if cs[1] ~= "第" then return false end
    local i = 2
    while cs[i] and NUMERALS[cs[i]] do i = i + 1 end
    return i > 2 and cs[i] ~= nil and CHAPTER_UNITS[cs[i]] == true
end

--- 在文字里找章节：{ {title=, b=字节位置}, ... }
local function findChapters(text)
    local out = {}
    for pos, line in text:gmatch("()([^\n]*)") do
        if #line > 0 and #line <= 120 and isChapterLine(line) then
            table.insert(out, { title = line:gsub("^[%s　]+", ""):gsub("[%s　]+$", ""), b = pos })
        end
    end
    return out
end

-- MARK: - 给 AI 的上下文：只到主人读过的位置为止（照抄 App 的 ReadingContext）

local Context = {
    chunk = 10000, -- 每一小段原文的长度（字）。超过这个长度的前文用摘要代替
    minRaw = 3000, -- 摘要和原文之间至少保留这么多原文
    group = 10,    -- 每 10 小段再合并一次摘要
}

local SUMMARY_SYSTEM = "你负责给小说做读书笔记式的摘要。只根据给你的文字，不要补充或猜测后面的剧情，即使你知道这本书。用简体中文。"

--- 章节：{ {title=, b=字节位置}, ... }，按位置排好
local function chapterAt(chapters, b)
    local lo, hi, ans = 1, #chapters, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if chapters[mid].b <= b then ans = mid; lo = mid + 1 else hi = mid - 1 end
    end
    if ans == 0 then return chapters[1] and chapters[1].title or "" end
    return chapters[ans].title
end

local function span(chapters, b0, b1)
    local a, c = chapterAt(chapters, b0), chapterAt(chapters, b1)
    if a == c then return a end
    return a .. " ～ " .. c
end

--- 在前文里找关键词：第一次出现 + 最近几次出现，各带一点上下文
function Context.search(terms, text, limit, chapters)
    local out = {}
    for _, term in ipairs(terms) do
        if utf8len(term) >= 2 and limit > 1 then
            local locs = {}
            local init = 1
            while #locs < 200 do
                local f = text:find(term, init, true)
                if not f or f + #term - 1 >= limit then break end
                table.insert(locs, f)
                init = f + #term
            end
            if #locs == 0 then
                table.insert(out, "「" .. term .. "」：在这之前的原文里没有出现过。")
            else
                local picks = { locs[1] }
                for i = math.max(1, #locs - 2), #locs do
                    local dup = false
                    for _, p in ipairs(picks) do if p == locs[i] then dup = true end end
                    if not dup then table.insert(picks, locs[i]) end
                end
                local lines = { "「" .. term .. "」：前文一共出现约 " .. #locs .. " 次。" }
                for _, l in ipairs(picks) do
                    local a = moveChars(text, l, -80)
                    local b = math.min(limit, moveChars(text, l + #term, 80))
                    local snip = text:sub(a, b - 1):gsub("\n", " ")
                    table.insert(lines, "  - 〔" .. chapterAt(chapters, l) .. "〕…" .. snip .. "…")
                end
                table.insert(out, table.concat(lines, "\n"))
            end
        end
    end
    return table.concat(out, "\n")
end

--- 从选中的句子和问题里挑出要去前文找的词
function Context.focusTerms(quote, question)
    local terms = {}
    local q = trim(quote)
    local n = utf8len(q)
    if n >= 2 and n <= 12 then table.insert(terms, q) end
    -- 问题里用引号括起来的词
    local pairs_ = { { "「", "」" }, { "“", "”" }, { "\"", "\"" }, { "『", "』" } }
    for _, pq in ipairs(pairs_) do
        local open, close = pq[1], pq[2]
        local init = 1
        while true do
            local a, a2 = question:find(open, init, true)
            if not a then break end
            local b = question:find(close, a2 + 1, true)
            if not b then break end
            local t = question:sub(a2 + 1, b - 1)
            local len = utf8len(t)
            if len >= 2 and len <= 12 then
                local dup = false
                for _, x in ipairs(terms) do if x == t then dup = true end end
                if not dup then table.insert(terms, t) end
            end
            init = b + #close
        end
    end
    while #terms > 3 do table.remove(terms) end
    return terms
end

function Context.system(title, persona, chapter_title, pct)
    local s = "你是主人的陪读朋友「" .. persona.display .. "」，正在和主人一起读《" .. title .. "》。\n"
        .. "你的性格：" .. persona.prompt .. "\n\n"
        .. "【铁律：绝对不剧透】\n"
        .. "- 主人现在读到「" .. chapter_title .. "」（全书大约 " .. pct .. "%）。你只读过下面给你的这些内容，就当你也刚好读到这里。\n"
        .. "- 绝对不要透露、暗示或\"预测\"后面的剧情，哪怕你本来就知道这本书（比如它很有名、被改编过）。不要说\"这个人后来会…\"\"注意这里是伏笔，之后…\"这类话。\n"
        .. "- 主人问到后面的事，就俏皮地说你也只读到这儿，一起往下看。可以一起好奇、一起猜，但只能根据已读内容猜，并说明是瞎猜。\n\n"
        .. "【怎么聊】\n"
        .. "- 像一起追书的朋友即时接话：口语化、有情绪、简短（一般 2 到 5 句），不要写成书评或长篇分析。\n"
        .. "- 主人问前面的情节或人物时，引用原文回答：用「」括住原句，说明大概在哪一章。前文和提要里找不到就直说没印象/没出现过，不要编。\n"
        .. "- 主人选中一句来吐槽时，先接住情绪，再说你的看法。\n"
        .. "- 不要用 # 标题和表格，可以偶尔用 **粗体**。"
    -- 墨水屏上显示不了 Markdown 粗体，多叮嘱一句
    s = s .. "\n- 主人在墨水屏阅读器上看你的回复，显示不了 Markdown，**粗体** 也尽量少用。"
    if not I18n.isChinese() then
        s = s .. "\n- Reply in English (the book text below may be in Chinese; quote it as-is)."
    end
    return s
end

-- MARK: - 插件本体

local ReadingBuddy = WidgetContainer:extend{
    name = "readingbuddy",
    is_doc_only = true,
}

function ReadingBuddy:onDispatcherRegisterActions()
    Dispatcher:registerAction("readingbuddy_chat", {
        category = "none", event = "ReadingBuddyChat", title = "Reading Buddy", reader = true,
    })
end

function ReadingBuddy:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.view and self.ui.registerTouchZones then
        self:setupCornerButton()
    end
    if self.ui.highlight then
        -- 按名字排序，放在「搜索」（12_search）前面
        self.ui.highlight:addToHighlightDialog("12_rb1_rant", function(this)
            return {
                text = L("吐槽这句"),
                callback = function()
                    local quote = util.cleanupSelectedText(this.selected_text and this.selected_text.text or "")
                    this:onClose()
                    self:askAbout(quote, "rant")
                end,
            }
        end)
        self.ui.highlight:addToHighlightDialog("12_rb2_ask", function(this)
            return {
                text = L("问一问"),
                callback = function()
                    local quote = util.cleanupSelectedText(this.selected_text and this.selected_text.text or "")
                    this:onClose()
                    self:askAbout(quote, "ask")
                end,
            }
        end)
    end
end

function ReadingBuddy:isSupported()
    return self.ui.rolling ~= nil and self.ui.document and self.ui.document.getTextFromXPointers ~= nil
end

-- MARK: 这本书的数据（存在 sidecar：书名.sdr/metadata.xxx.lua）

function ReadingBuddy:bookData()
    local d = self.ui.doc_settings:readSetting("readingbuddy")
    if type(d) ~= "table" then d = {} end
    d.chat = d.chat or {}
    d.summaries = d.summaries or {}
    return d
end

function ReadingBuddy:saveBookData(d)
    self.ui.doc_settings:saveSetting("readingbuddy", d)
    self.ui.doc_settings:flush()
end

function ReadingBuddy:bookTitle()
    local props = self.ui.doc_props
    if props and props.display_title and props.display_title ~= "" then return props.display_title end
    local _, name = util.splitFilePathName(self.document.file or "")
    return util.splitFileNameSuffix(name or "")
end

-- MARK: 读到哪儿了

--- 当前屏幕最后一个字的位置
function ReadingBuddy:screenEnd()
    local doc = self.ui.document
    -- 翻页模式：下一页的开头正好是这一页最后一个字之后（最准）
    if self.ui.view and self.ui.view.view_mode == "page" then
        local page = doc:getCurrentPage()
        -- 双页模式下一屏有两页
        if self.ui.document:getVisiblePageCount() == 2 then page = page + 1 end
        if page < doc:getPageCount() then
            local xp = doc:getPageXPointer(page + 1)
            if xp then return xp end
        end
    end
    local ok, r = pcall(function()
        return doc:getTextFromPositions({ x = 0, y = 0 }, { x = Screen:getWidth() - 1, y = Screen:getHeight() - 1 }, true)
    end)
    if ok and r and r.pos1 then return r.pos1 end
    local page = doc:getCurrentPage()
    if page < doc:getPageCount() then return doc:getPageXPointer(page + 1) end
    return doc:getXPointer()
end

--- 翻页时记下读到的最远位置（AI 只看得到它之前的内容）
function ReadingBuddy:updateFurthest()
    if not self:isSupported() then return end
    local cur = self:screenEnd()
    if not cur then return end
    local d = self:bookData()
    local f = d.furthest
    local cmp = f and self.ui.document:compareXPointers(f, cur)
    if not f or cmp == nil or cmp > 0 then
        d.furthest = cur
        self.ui.doc_settings:saveSetting("readingbuddy", d)
    end
end

function ReadingBuddy:onPageUpdate()
    if self._furthest_scheduled then return end
    self._furthest_scheduled = true
    UIManager:nextTick(function()
        self._furthest_scheduled = false
        pcall(self.updateFurthest, self)
    end)
end

function ReadingBuddy:onReaderReady()
    pcall(self.updateFurthest, self)
end

function ReadingBuddy:furthest()
    local d = self:bookData()
    return d.furthest or self:screenEnd()
end

--- xp 在第几页。xp 正好是某页的开头（= 上一页刚读完）时算上一页
function ReadingBuddy:pageOf(xp)
    local doc = self.ui.document
    local page = doc:getPageFromXPointer(xp) or 1
    if page > 1 and doc:getPageXPointer(page) == xp then page = page - 1 end
    return page
end

function ReadingBuddy:chapterTitleAt(xp)
    -- 上次聊天时按文字算好的章节名最准
    local c = self:bookData().chapter_at
    if c and c.xp == xp then return c.title end
    local page = self:pageOf(xp)
    local t = self.ui.toc and self.ui.toc:getTocTitleByPage(page)
    if t and t ~= "" then return t end
    return L("第 %d 页", page)
end

--- 取「全书开头 → 读到的最远位置」的文字，并按目录记下每章的开头
function ReadingBuddy:readText(end_xp)
    local doc = self.ui.document
    local start_xp = doc:getPageXPointer(1)
    self.ui.toc:fillToc()
    local marks = {}
    for _, item in ipairs(self.ui.toc.toc or {}) do
        local xp = item.xpointer
        if xp then
            local before_end = doc:compareXPointers(xp, end_xp)
            local after_start = doc:compareXPointers(start_xp, xp)
            if before_end and before_end > 0 and after_start and after_start >= 0 then
                local last = marks[#marks]
                if not last or (doc:compareXPointers(last.xp, xp) or 0) > 0 then
                    table.insert(marks, { xp = xp, title = trim(item.title or "") })
                elseif last and doc:compareXPointers(last.xp, xp) == 0 then
                    last.title = trim(item.title or "") -- 同一位置有几级目录，用最细的那个
                end
            end
        end
    end
    local pieces, chapters = {}, {}
    local len = 0
    local function add(a, b, title)
        if (doc:compareXPointers(a, b) or 0) <= 0 then
            if title then table.insert(chapters, { title = title, b = len + 1 }) end
            return
        end
        local t = doc:getTextFromXPointers(a, b, false) or ""
        if t ~= "" and len > 0 and not t:match("^\n") then t = "\n" .. t end
        if title then table.insert(chapters, { title = title, b = len + 1 }) end
        table.insert(pieces, t)
        len = len + #t
    end
    local first = marks[1] and marks[1].xp or end_xp
    add(start_xp, first, nil)
    for i, m in ipairs(marks) do
        local stop = marks[i + 1] and marks[i + 1].xp or end_xp
        add(m.xp, stop, m.title)
    end
    local text = table.concat(pieces)
    -- 没有目录（txt 常见）：自己按「第X章/回/卷…、序章、楔子、番外、Chapter N」找章节
    if #chapters == 0 then chapters = findChapters(text) end
    if #chapters == 0 or chapters[1].b > 1 then
        table.insert(chapters, 1, { title = #chapters == 0 and self:bookTitle() or L("开篇"), b = 1 })
    end
    return text, chapters
end

--- 缺少的摘要先补齐（会调用 AI），返回给 AI 看的完整上下文。出错返回 nil, 错误
function ReadingBuddy:buildContext(text, chapters, focus_terms, progress)
    local C = Context
    local marks, total = charMarks(text, C.chunk)
    local chunk_start = math.max(0, math.floor((total - C.minRaw) / C.chunk)) * C.chunk
    local chunk_count = chunk_start / C.chunk
    local function byteOf(k) return marks[k] or (#text + 1) end
    -- 原文从下一段开头开始，不要从半句话开始（中间这一点点摘要里已经有了）
    local raw_from = byteOf(chunk_count)
    if raw_from > 1 then
        local window_end = math.min(#text, moveChars(text, raw_from, 400))
        local nl = text:find("\n", raw_from, true)
        if nl and nl < window_end then raw_from = nl + 1 end
    end

    local d = self:bookData()
    local sums = d.summaries
    local title = self:bookTitle()
    local full_groups = math.floor(chunk_count / C.group)

    -- 补齐摘要
    local missing0, missing1 = {}, {}
    for i = 0, chunk_count - 1 do
        local covered = i < full_groups * C.group and sums["1-" .. math.floor(i / C.group)]
        if not sums["0-" .. i] and not covered then table.insert(missing0, i) end
    end
    for g = 0, full_groups - 1 do
        if not sums["1-" .. g] then table.insert(missing1, g) end
    end
    local todo = #missing0 + #missing1
    local done = 0
    if todo > 0 and progress(done, todo) == false then return nil end
    for _, i in ipairs(missing0) do
        local b0, b1 = byteOf(i), byteOf(i + 1)
        local raw = text:sub(b0, b1 - 1)
        local place = span(chapters, b0, b1 - 1):gsub(" ～ ", "」到「")
        local reply, err = AI.send(SUMMARY_SYSTEM, { { role = "user", text =
            "这是小说《" .. title .. "》中的一段原文（大约在「" .. place .. "」）。请用 200 字以内概括这段发生了什么；然后另起一行写「人物：」，列出这段里出场的人物（一行一个，格式「名字：身份、和谁什么关系、做了什么」）。不要写这段以外的内容。\n\n" .. raw,
        } }, 1200)
        if not reply then return nil, err end
        sums["0-" .. i] = { text = reply, b0 = b0, b1 = b1 }
        self:saveBookData(d)
        done = done + 1
        if progress(done, todo) == false then return nil end
    end
    for _, g in ipairs(missing1) do
        local parts = {}
        for i = g * C.group, (g + 1) * C.group - 1 do
            if sums["0-" .. i] then table.insert(parts, sums["0-" .. i].text) end
        end
        local reply, err = AI.send(SUMMARY_SYSTEM, { { role = "user", text =
            "下面是小说《" .. title .. "》连续 " .. #parts .. " 段的摘要。请合并成一份不超过 400 字的剧情概要，保留关键事件、转折和伏笔；最后另起一行写「人物：」，列出这部分出现的重要人物和身份/关系（一行一个，格式「名字：说明」）。\n\n" .. table.concat(parts, "\n\n"),
        } }, 2000)
        if not reply then return nil, err end
        sums["1-" .. g] = { text = reply, b0 = byteOf(g * C.group), b1 = byteOf((g + 1) * C.group) }
        self:saveBookData(d)
        done = done + 1
        if progress(done, todo) == false then return nil end
    end

    local s = {}
    -- 前情提要：整组的用合并摘要，剩下的用小段摘要
    local recap = {}
    for g = 0, full_groups - 1 do
        local c = sums["1-" .. g]
        if c then table.insert(recap, "〔" .. span(chapters, c.b0, c.b1 - 1) .. "〕" .. c.text) end
    end
    for i = full_groups * C.group, chunk_count - 1 do
        local c = sums["0-" .. i]
        if c then table.insert(recap, "〔" .. span(chapters, c.b0, c.b1 - 1) .. "〕" .. c.text) end
    end
    if #recap > 0 then
        table.insert(s, "【前情提要（主人已经读过的部分，按顺序）】\n" .. table.concat(recap, "\n\n") .. "\n\n")
    end

    -- 主人问到的词在前文出现过的地方（摘要里可能没写到）
    local hits = Context.search(focus_terms, text, raw_from, chapters)
    if hits ~= "" then table.insert(s, "【前文里提到这些词的地方】\n" .. hits .. "\n\n") end

    table.insert(s, "【主人刚刚读过的原文（从「" .. chapterAt(chapters, raw_from) .. "」开始，到主人现在的位置「"
        .. chapterAt(chapters, #text) .. "」为止）】\n")
    table.insert(s, text:sub(raw_from))
    table.insert(s, "\n【原文到此为止，主人还没往下读】")
    return table.concat(s)
end

-- MARK: 聊天

local function messageText(line)
    if line.role ~= "user" or not line.quote or line.quote == "" then return line.text end
    local head = "【我选中了这句】「" .. line.quote .. "」\n"
    if line.kind == "rant" then
        return head .. (line.text == "" and "（我把这句划出来了，你接一句吧）" or ("我想吐槽：" .. line.text))
    elseif line.kind == "ask" then
        return head .. (line.text == "" and "这句是什么意思？前面有相关的内容吗？" or ("我想问：" .. line.text))
    end
    return head .. line.text
end

--- 发一句话（可以带选中的句子）。kind = "rant" / "ask" / ""
function ReadingBuddy:send(text, quote, kind)
    if not self:isSupported() then
        UIManager:show(InfoMessage:new{ text = L("这本书的格式不支持。Reading Buddy 目前只支持 epub、txt、fb2、mobi 这类可以重排的书（PDF、漫画不行）。") })
        return
    end
    text = trim(text)
    quote = trim(quote)
    if text == "" and quote == "" then text = L("（读到这儿了，你想说点啥？）") end

    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function()
            self:doSend(text, quote, kind)
        end)
    end)
end

function ReadingBuddy:doSend(text, quote, kind)
    pcall(self.updateFurthest, self)
    local d = self:bookData()
    local end_xp = self:furthest()
    table.insert(d.chat, { role = "user", text = text, quote = quote, kind = kind })
    self:saveBookData(d)

    Trapper:info(L("翻翻前文…"))
    local reply, err
    local text_before, chapters = self:readText(end_xp)
    -- 记下这个位置是哪一章（没有目录的书，聊天窗口标题要用）
    d = self:bookData()
    d.chapter_at = { xp = end_xp, title = chapterAt(chapters, #text_before) }
    self:saveBookData(d)
    if text_before == "" then
        err = L("还没读到正文呢，往后翻几页再来聊吧。")
    else
        local terms = Context.focusTerms(quote, text)
        local ctx
        ctx, err = self:buildContext(text_before, chapters, terms, function(done, total)
            return Trapper:info(L("第一次聊这本书，先补一下前情提要（%d/%d）…", done, total))
        end)
        if ctx then
            Trapper:info(L("正在想…"))
            local doc = self.ui.document
            local pct = math.floor(self:pageOf(end_xp) / math.max(1, doc:getPageCount()) * 100)
            local system = Context.system(self:bookTitle(), Config.persona(), chapterAt(chapters, #text_before), pct)
                .. "\n\n" .. ctx
            -- 最近 20 句，Anthropic 要求从 user 开始、user/assistant 交替
            d = self:bookData()
            local history = {}
            for _, l in ipairs(d.chat) do
                if not l.err then table.insert(history, l) end
            end
            local msgs = {}
            for i = math.max(1, #history - 19), #history do
                local l = history[i]
                local m = { role = l.role, text = messageText(l) }
                local last = msgs[#msgs]
                if last and last.role == m.role then
                    last.text = last.text .. "\n\n" .. m.text
                elseif #msgs > 0 or m.role == "user" then
                    table.insert(msgs, m)
                end
            end
            reply, err = AI.send(system, msgs, 2000)
        elseif not err then
            -- 主人中途点了取消
            Trapper:clear()
            return
        end
    end
    Trapper:clear()

    d = self:bookData()
    if reply then
        table.insert(d.chat, { role = "assistant", text = reply })
    else
        table.insert(d.chat, { role = "assistant", text = err or L("AI 没有返回内容，请重试。"), err = true })
    end
    while #d.chat > 300 do table.remove(d.chat, 1) end
    self:saveBookData(d)
    self:showChat()
end

--- 划线后的「吐槽这句」「问一问」
function ReadingBuddy:askAbout(quote, kind)
    local dialog
    dialog = InputDialog:new{
        title = kind == "rant" and L("吐槽这句") or L("问一问"),
        description = "「" .. quote .. "」",
        input = "",
        input_hint = kind == "rant" and L("想吐槽什么？（可以不写，直接发送）") or L("想问什么？（可以不写，直接发送）"),
        allow_newline = false,
        buttons = { {
            { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = L("发送"), is_enter_default = true, callback = function()
                local t = dialog:getInputText()
                UIManager:close(dialog)
                self:send(t, quote, kind)
            end },
        } },
    }
    UIManager:show(dialog)
end

--- 「说点什么」输入框
--- 「聊聊」输入框：可以打字，也可以直接点快捷句，不用打字
local QUICK = {
    { "这人是谁来着？", "这页这个人是谁来着？前面出现过吗？" },
    { "前面发生了啥？", "帮我简单回顾一下前面发生了什么。" },
    { "气死我了！", "这一段看得我好气，你说说！" },
    { "你怎么看？", "读到这儿你怎么看？" },
}

function ReadingBuddy:compose(show_keyboard)
    local dialog
    local function send(t)
        UIManager:close(dialog)
        self:send(t, "", "")
    end
    local quick_rows = {}
    for i = 1, #QUICK, 2 do
        local row = {}
        for j = i, math.min(i + 1, #QUICK) do
            local q = QUICK[j]
            table.insert(row, { text = L(q[1]), callback = function() send(L(q[2])) end })
        end
        table.insert(quick_rows, row)
    end
    local buttons = quick_rows
    table.insert(buttons, {
        { text = L("聊天记录"), callback = function()
            UIManager:close(dialog)
            self:showChat()
        end },
        { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
        { text = L("发送"), is_enter_default = true, callback = function() send(dialog:getInputText()) end },
    })
    dialog = InputDialog:new{
        title = L("跟%s聊聊", Config.persona().display),
        input = "",
        input_hint = L("想说什么？（可以不写，直接发送）"),
        allow_newline = false,
        buttons = buttons,
    }
    UIManager:show(dialog)
    if show_keyboard then dialog:onShowKeyboard() end
end

-- MARK: 页面右下角的「聊聊」小按钮（像手机上那样点一下就能聊）

function ReadingBuddy:buttonEnabled()
    return Config.get("corner_button", true) and self:isSupported()
end

local PERSONA_ICONS = { snark = "girl_twin", gentle = "girl_long", scholar = "girl_glasses", custom = "girl_bun" }

--- 按钮是陪读朋友的小人头（跟手机上一样：毒舌搭子双马尾、温柔解答长发、考据党眼镜、自定义丸子头）
function ReadingBuddy:buttonWidget()
    local icon = PERSONA_ICONS[Config.persona().id] or "girl_twin"
    if not self._button or self._button_icon ~= icon then
        if self._button then self._button:free() end
        local size = Screen:scaleBySize(60)
        self._button = ImageWidget:new{
            file = self.path .. "/icons/" .. icon .. ".svg",
            width = size,
            height = size,
            alpha = true,
        }
        self._button_icon = icon
    end
    return self._button
end

function ReadingBuddy:buttonRect()
    local w = self:buttonWidget()
    local sz = w:getSize()
    local view = self.ui.view
    local footer_h = (view and view.footer_visible and view.footer) and view.footer:getHeight() or 0
    local margin = Screen:scaleBySize(6)
    return Geom:new{
        x = Screen:getWidth() - sz.w - margin,
        y = Screen:getHeight() - footer_h - sz.h - margin,
        w = sz.w, h = sz.h,
    }
end

function ReadingBuddy:setupCornerButton()
    local plugin = self
    self.ui.view:registerViewModule("readingbuddy_button", {
        paintTo = function(_, bb, x, y)
            if not plugin:buttonEnabled() then return end
            local r = plugin:buttonRect()
            plugin:buttonWidget():paintTo(bb, x + r.x, y + r.y)
        end,
    })
    -- 点击区域比按钮大一圈，手指好点
    self.ui:registerTouchZones({
        {
            id = "readingbuddy_button_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0.8, ratio_y = 0.84, ratio_w = 0.2, ratio_h = 0.16 },
            handler = function(ges)
                if not plugin:buttonEnabled() then return end
                local r = plugin:buttonRect()
                local pad = Screen:scaleBySize(24)
                local hit = Geom:new{ x = r.x - pad, y = r.y - pad, w = r.w + 2 * pad, h = r.h + 2 * pad }
                if not ges.pos:intersectWith(hit) then return end
                plugin:compose()
                return true
            end,
            overrides = {
                "tap_forward", "tap_backward", "readerconfigmenu_tap", "readerconfigmenu_ext_tap",
                "readerfooter_tap", "tap_right_bottom_corner",
            },
        },
    })
end

function ReadingBuddy:chatText()
    local d = self:bookData()
    local colon = I18n.isChinese() and "：\n" or ":\n"
    local persona = Config.persona()
    local lines = {}
    if #d.chat == 0 then
        table.insert(lines, persona.display .. colon .. L("读到哪儿想吐槽、有看不懂的，直接跟我说。也可以在书里长按选中一句，点「吐槽这句」或「问一问」。我只看得到你读过的部分，放心不剧透。"))
    end
    for _, l in ipairs(d.chat) do
        if l.role == "user" then
            local head = L("我")
            if l.kind == "rant" then head = head .. " · " .. L("吐槽") elseif l.kind == "ask" then head = head .. " · " .. L("提问") end
            local body = {}
            if l.quote and l.quote ~= "" then table.insert(body, "「" .. l.quote .. "」") end
            if l.text and l.text ~= "" then table.insert(body, l.text) end
            table.insert(lines, "▶ " .. head .. colon .. table.concat(body, "\n"))
        else
            local who = persona.display
            table.insert(lines, who .. colon .. (l.err and ("⚠ " .. l.text) or l.text))
        end
    end
    return table.concat(lines, "\n\n")
end

function ReadingBuddy:showChat()
    if not self:isSupported() then
        UIManager:show(InfoMessage:new{ text = L("这本书的格式不支持。Reading Buddy 目前只支持 epub、txt、fb2、mobi 这类可以重排的书（PDF、漫画不行）。") })
        return
    end
    local persona = Config.persona()
    local viewer
    viewer = TextViewer:new{
        title = L("%s只读到「%s」，不会剧透", persona.display, self:chapterTitleAt(self:furthest())),
        title_multilines = true,
        text = self:chatText(),
        justified = false,
        buttons_table = { {
            { text = L("清空聊天"), callback = function()
                UIManager:show(ConfirmBox:new{
                    text = L("要清空这本书的聊天记录吗？"),
                    ok_text = L("清空"),
                    ok_callback = function()
                        local d = self:bookData()
                        d.chat = {}
                        self:saveBookData(d)
                        UIManager:close(viewer)
                        self:showChat()
                    end,
                })
            end },
            { text = L("关闭"), callback = function() UIManager:close(viewer) end },
            { text = L("说点什么"), callback = function()
                UIManager:close(viewer)
                self:compose()
            end },
        } },
    }
    viewer.scroll_widget:scrollToBottom()
    UIManager:show(viewer)
end

function ReadingBuddy:onReadingBuddyChat()
    self:showChat()
    return true
end

-- MARK: 菜单

function ReadingBuddy:addToMainMenu(menu_items)
    menu_items.readingbuddy = {
        text = "Reading Buddy",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = L("打开聊天"),
                callback = function() self:showChat() end,
            },
            {
                text = L("页面右下角显示陪读小人头"),
                checked_func = function() return Config.get("corner_button", true) end,
                callback = function()
                    Config.set("corner_button", not Config.get("corner_button", true))
                    UIManager:setDirty("all", "ui")
                end,
            },
            {
                text_func = function() return L("陪读性格：%s", Config.persona().display) end,
                sub_item_table_func = function() return self:personaMenu() end,
            },
            {
                text = L("AI 设置"),
                sub_item_table_func = function() return self:aiMenu() end,
            },
            {
                text = L("这本书的设置"),
                sub_item_table_func = function() return self:bookMenu() end,
            },
            {
                text = L("说明"),
                keep_menu_open = true,
                callback = function()
                    local about = I18n.isChinese() and
                        "Reading Buddy 是只看得到你读过的内容的 AI 陪读朋友。\n\n"
                        .. "· 长按选中一句，点「吐槽这句」或「问一问」。\n"
                        .. "· 也可以在「Reading Buddy › 打开聊天」里聊，不打字直接点「发送」也行。\n"
                        .. "· 只有「读到的最远位置」之前的内容会发给你选的 AI 服务商；更早的部分会先做成简短的前情提要，存在这本书旁边的 .sdr 文件夹里，下次不用重做。\n"
                        .. "· API Key 以明文保存在这台阅读器的 KOReader 设置文件 settings.reader.lua 里。\n"
                        .. "· 需要连 Wi-Fi。"
                        or L("说明正文")
                    UIManager:show(InfoMessage:new{ text = about })
                end,
            },
        },
    }
end

function ReadingBuddy:personaMenu()
    local items = {}
    for _, p in ipairs(PERSONAS) do
        table.insert(items, {
            text = L(p.name) .. " · " .. L(p.tagline),
            radio = true,
            checked_func = function() return Config.get("persona", "snark") == p.id end,
            callback = function() Config.set("persona", p.id) end,
        })
    end
    table.insert(items, {
        text_func = function()
            if Config.get("persona") == CUSTOM_ID then
                local p = Config.persona()
                return L("自定义") .. " · " .. p.display
            end
            return L("自定义") .. " · " .. L("自己写性格")
        end,
        radio = true,
        checked_func = function() return Config.get("persona") == CUSTOM_ID end,
        callback = function(touchmenu_instance)
            Config.set("persona", CUSTOM_ID)
            self:editCustomPersona(touchmenu_instance)
        end,
    })
    return items
end

function ReadingBuddy:editCustomPersona(touchmenu_instance)
    local dialog
    dialog = MultiInputDialog:new{
        title = L("编辑自定义性格"),
        fields = {
            { text = Config.get("custom_name", ""), hint = L("名字") },
            { text = Config.get("custom_desc", ""), hint = L("性格说明（写给 AI 看的，比如：说话像古代书生，爱掉书袋）") },
        },
        buttons = { {
            { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = L("保存"), callback = function()
                local f = dialog:getFields()
                Config.set("custom_name", trim(f[1]))
                Config.set("custom_desc", trim(f[2]))
                UIManager:close(dialog)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function ReadingBuddy:aiMenu()
    local items = {}
    -- 服务商
    local providers = {}
    for _, p in ipairs(PROVIDERS) do
        table.insert(providers, {
            text = L(p.name),
            radio = true,
            checked_func = function() return Config.provider().id == p.id end,
            callback = function() Config.set("provider", p.id) end,
        })
    end
    table.insert(items, {
        text_func = function() return L("服务商：%s", L(Config.provider().name)) end,
        sub_item_table = providers,
    })
    table.insert(items, {
        text_func = function()
            return L("API Key：%s", Config.key(Config.provider()) ~= "" and L("已填写") or L("未填写"))
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance) self:editKey(touchmenu_instance) end,
    })
    table.insert(items, {
        text_func = function()
            local m = Config.model(Config.provider())
            return L("模型：%s", m ~= "" and m or L("（未选择）"))
        end,
        sub_item_table_func = function() return self:modelMenu() end,
    })
    table.insert(items, {
        text_func = function()
            local b = Config.baseURL(Config.provider())
            return L("接口地址：%s", b ~= "" and b or L("（未选择）"))
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance) self:editBase(touchmenu_instance) end,
    })
    table.insert(items, {
        text = L("测试连接"),
        keep_menu_open = true,
        callback = function()
            NetworkMgr:runWhenOnline(function()
                Trapper:wrap(function()
                    Trapper:info(L("正在想…"))
                    local reply, err = AI.send("Reply with one short friendly sentence.", { { role = "user", text = "Hi!" } }, 200)
                    Trapper:clear()
                    UIManager:show(InfoMessage:new{ text = reply and L("连接成功！AI 回复：\n\n%s", reply) or err })
                end)
            end)
        end,
    })
    return items
end

function ReadingBuddy:editKey(touchmenu_instance)
    local p = Config.provider()
    local dialog
    dialog = InputDialog:new{
        title = "API Key · " .. L(p.name),
        description = L("在服务商的控制台创建 API Key（%s）。\n\n注意：Key 会以明文保存在这台阅读器的 KOReader 设置文件 settings.reader.lua 里，不要把这个文件分享给别人。",
            p.signup ~= "" and p.signup or "-"),
        input = Config.key(p),
        text_type = "password",
        buttons = { {
            { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = L("从文件读取"), callback = function()
                UIManager:close(dialog)
                self:keyFromFile(p, touchmenu_instance)
            end },
            { text = L("保存"), is_enter_default = true, callback = function()
                Config.setFor("keys", p.id, trim(dialog:getInputText()))
                UIManager:close(dialog)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- 墨水屏上打长长的 Key 太累：可以在电脑上把 Key 存成 readingbuddy-key.txt，拷进 koreader 文件夹再读进来
function ReadingBuddy:keyFromFile(p, touchmenu_instance)
    local path = DataStorage:getDataDir() .. "/readingbuddy-key.txt"
    local f = io.open(path, "r")
    if not f then
        UIManager:show(InfoMessage:new{ text = L("没找到 %s\n\n在电脑上新建一个纯文本文件，里面只写 API Key，文件名叫 readingbuddy-key.txt，用数据线拷进阅读器的 koreader 文件夹（Kobo 是 .adds/koreader），再点一次「从文件读取」。", path) })
        return
    end
    local key = trim(f:read("*a") or ""):gsub("^\239\187\191", "")
    f:close()
    if key == "" then
        UIManager:show(InfoMessage:new{ text = L("文件是空的，请在里面写上 API Key。") })
        return
    end
    Config.setFor("keys", p.id, key)
    if touchmenu_instance then touchmenu_instance:updateItems() end
    UIManager:show(ConfirmBox:new{
        text = L("已读取 %s 的 API Key。\n\n为了安全，要把阅读器里的 readingbuddy-key.txt 删掉吗？（Key 已经存进设置了）", L(p.name)),
        ok_text = L("删掉文件"),
        cancel_text = L("先留着"),
        ok_callback = function() os.remove(path) end,
    })
end

function ReadingBuddy:editBase(touchmenu_instance)
    local p = Config.provider()
    local dialog
    dialog = InputDialog:new{
        title = L("接口地址") .. " · " .. L(p.name),
        description = p.note and L(p.note) or nil,
        input = Config.baseURL(p),
        input_hint = "https://…/v1",
        buttons = { {
            { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = L("恢复默认"), callback = function()
                Config.setFor("bases", p.id, nil)
                UIManager:close(dialog)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
            { text = L("保存"), is_enter_default = true, callback = function()
                local b = trim(dialog:getInputText())
                Config.setFor("bases", p.id, b ~= p.base and b or nil)
                UIManager:close(dialog)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function ReadingBuddy:modelMenu()
    local p = Config.provider()
    local items = {}
    local list = {}
    for _, m in ipairs(p.models) do table.insert(list, m) end
    local cur = Config.model(p)
    local found = false
    for _, m in ipairs(list) do if m == cur then found = true end end
    if cur ~= "" and not found then table.insert(list, 1, cur) end
    for _, m in ipairs(list) do
        table.insert(items, {
            text = m,
            radio = true,
            checked_func = function() return Config.model(p) == m end,
            callback = function() Config.setFor("models", p.id, m) end,
        })
    end
    table.insert(items, {
        text = L("手动填写模型名…"),
        keep_menu_open = true,
        separator = false,
        callback = function(touchmenu_instance)
            local dialog
            dialog = InputDialog:new{
                title = L("模型名"),
                description = p.note and L(p.note) or nil,
                input = Config.model(p),
                buttons = { {
                    { text = L("取消"), id = "close", callback = function() UIManager:close(dialog) end },
                    { text = L("保存"), is_enter_default = true, callback = function()
                        Config.setFor("models", p.id, trim(dialog:getInputText()))
                        UIManager:close(dialog)
                        if touchmenu_instance then touchmenu_instance:backToUpperMenu() end
                    end },
                } },
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end,
    })
    table.insert(items, {
        text = L("从服务商获取模型列表…"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            NetworkMgr:runWhenOnline(function()
                Trapper:wrap(function()
                    Trapper:info(L("正在获取模型列表…"))
                    local ids, err = AI.fetchModels(p)
                    Trapper:clear()
                    if not ids then
                        UIManager:show(InfoMessage:new{ text = err })
                    elseif #ids == 0 then
                        UIManager:show(InfoMessage:new{ text = L("这个服务商没有返回模型列表，请手动填写模型名。") })
                    else
                        self:pickModel(p, ids, touchmenu_instance)
                    end
                end)
            end)
        end,
    })
    return items
end

function ReadingBuddy:pickModel(p, ids, touchmenu_instance)
    local menu
    local item_table = {}
    for _, id in ipairs(ids) do
        table.insert(item_table, { text = id, model_id = id, checked = Config.model(p) == id })
    end
    menu = Menu:new{
        title = L("选择模型"),
        item_table = item_table,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuChoice = function(_, item)
            Config.setFor("models", p.id, item.model_id)
            if touchmenu_instance then touchmenu_instance:backToUpperMenu() end
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function ReadingBuddy:bookMenu()
    return {
        {
            text_func = function()
                if not self:isSupported() then return L("读到的最远位置：%s", L("未知")) end
                return L("读到的最远位置：%s", self:chapterTitleAt(self:furthest()))
            end,
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{ text = L("AI 只会看到「读到的最远位置」之前的内容。如果你往后跳着翻过，可以在这里改回当前页。") })
            end,
        },
        {
            text = L("把「读到的最远位置」改成当前页"),
            enabled_func = function() return self:isSupported() end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local d = self:bookData()
                d.furthest = self:screenEnd()
                self:saveBookData(d)
                UIManager:show(InfoMessage:new{ text = L("已改成当前页：%s", self:chapterTitleAt(d.furthest)), timeout = 2 })
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = L("清空聊天"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = L("要清空这本书的聊天记录吗？"),
                    ok_text = L("清空"),
                    ok_callback = function()
                        local d = self:bookData()
                        d.chat = {}
                        self:saveBookData(d)
                    end,
                })
            end,
        },
        {
            text = L("重做前情提要"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = L("前情提要是 AI 帮你做的读书笔记，下次聊天时会重新做（会多花一点额度）。要重做吗？"),
                    ok_text = L("重做"),
                    ok_callback = function()
                        local d = self:bookData()
                        d.summaries = {}
                        self:saveBookData(d)
                        UIManager:show(InfoMessage:new{ text = L("已清空，下次聊天时重新做。"), timeout = 2 })
                    end,
                })
            end,
        },
    }
end

return ReadingBuddy
