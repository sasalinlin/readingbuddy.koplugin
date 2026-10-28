-- Reading Buddy 的中英文界面。key 是中文原文，跟随 KOReader 的界面语言：
-- 中文（zh 开头）显示原文，其他语言显示英文。
local _ = require("gettext")

local EN = {
    -- 性格
    ["毒舌搭子"] = "Snarky Pal",
    ["嘴毒心软，陪你一起骂角色"] = "Sharp tongue, soft heart. Roasts the characters with you",
    ["温柔解答"] = "Gentle Guide",
    ["耐心细致，有问必答"] = "Patient and thorough, answers everything",
    ["考据党"] = "Detail Detective",
    ["细节控，伏笔雷达"] = "Obsessed with details and foreshadowing",
    ["我的书友"] = "My Buddy",
    ["自己写性格"] = "Write your own personality",
    ["自定义"] = "Custom",
    ["编辑自定义性格"] = "Edit custom personality",
    ["名字"] = "Name",
    ["性格说明（写给 AI 看的，比如：说话像古代书生，爱掉书袋）"] = "Personality (for the AI, e.g. talks like an old-time scholar)",

    -- 划线菜单 / 聊天
    ["吐槽这句"] = "Rant",
    ["问一问"] = "Ask",
    ["想吐槽什么？（可以不写，直接发送）"] = "What's your rant? (optional, you can just send)",
    ["想问什么？（可以不写，直接发送）"] = "What do you want to ask? (optional, you can just send)",
    ["想说什么？（可以不写，直接发送）"] = "Say something (optional, you can just send)",
    ["发送"] = "Send",
    ["取消"] = "Cancel",
    ["关闭"] = "Close",
    ["说点什么"] = "Say something",
    ["清空聊天"] = "Clear chat",
    ["打开聊天"] = "Open chat",
    ["（读到这儿了，你想说点啥？）"] = "(I've read up to here. Any thoughts?)",
    ["我"] = "Me",
    ["吐槽"] = "Rant",
    ["提问"] = "Ask",
    ["%s只读到「%s」，不会剧透"] = "%s has only read up to \"%s\" - no spoilers",
    ["读到哪儿想吐槽、有看不懂的，直接跟我说。也可以在书里长按选中一句，点「吐槽这句」或「问一问」。我只看得到你读过的部分，放心不剧透。"] = "Want to rant or got confused? Just tell me. You can also long-press a line in the book and tap \"Rant\" or \"Ask\". I can only see what you've already read, so no spoilers.",
    ["翻翻前文…"] = "Flipping back through the pages...",
    ["第一次聊这本书，先补一下前情提要（%d/%d）…"] = "First chat about this book, catching up on the story so far (%d/%d)...",
    ["正在想…"] = "Thinking...",
    ["要清空这本书的聊天记录吗？"] = "Clear the chat history for this book?",
    ["清空"] = "Clear",
    ["这本书的格式不支持。Reading Buddy 目前只支持 epub、txt、fb2、mobi 这类可以重排的书（PDF、漫画不行）。"] = "This format isn't supported. Reading Buddy works with reflowable books like epub, txt, fb2 and mobi (not PDF or comics).",
    ["还没读到正文呢，往后翻几页再来聊吧。"] = "You haven't read anything yet. Turn a few pages and come back!",

    -- 菜单
    ["陪读性格"] = "Personality",
    ["陪读性格：%s"] = "Personality: %s",
    ["AI 设置"] = "AI settings",
    ["服务商：%s"] = "Provider: %s",
    ["API Key：%s"] = "API key: %s",
    ["已填写"] = "set",
    ["未填写"] = "not set",
    ["模型：%s"] = "Model: %s",
    ["（未选择）"] = "(none)",
    ["接口地址"] = "API URL",
    ["接口地址：%s"] = "API URL: %s",
    ["测试连接"] = "Test connection",
    ["连接成功！AI 回复：\n\n%s"] = "Connected! The AI said:\n\n%s",
    ["手动填写模型名…"] = "Type a model name...",
    ["从服务商获取模型列表…"] = "Fetch models from provider...",
    ["这个服务商没有返回模型列表，请手动填写模型名。"] = "This provider didn't return a model list. Please type a model name.",
    ["正在获取模型列表…"] = "Fetching models...",
    ["选择模型"] = "Choose a model",
    ["模型名"] = "Model name",
    ["保存"] = "Save",
    ["恢复默认"] = "Reset",
    ["在服务商的控制台创建 API Key（%s）。\n\n注意：Key 会以明文保存在这台阅读器的 KOReader 设置文件 settings.reader.lua 里，不要把这个文件分享给别人。"] = "Create an API key in your provider's console (%s).\n\nNote: the key is saved as plain text in KOReader's settings file settings.reader.lua on this device. Don't share that file.",
    ["这本书的设置"] = "This book",
    ["读到的最远位置：%s"] = "Furthest read: %s",
    ["把「读到的最远位置」改成当前页"] = "Set \"furthest read\" to this page",
    ["AI 只会看到「读到的最远位置」之前的内容。如果你往后跳着翻过，可以在这里改回当前页。"] = "The AI only sees text before your \"furthest read\" position. If you skipped ahead, you can reset it to this page here.",
    ["已改成当前页：%s"] = "Set to this page: %s",
    ["重做前情提要"] = "Redo story-so-far summaries",
    ["前情提要是 AI 帮你做的读书笔记，下次聊天时会重新做（会多花一点额度）。要重做吗？"] = "The story-so-far summaries will be rebuilt next time you chat (uses a little more API credit). Redo them?",
    ["重做"] = "Redo",
    ["已清空，下次聊天时重新做。"] = "Cleared. They'll be rebuilt next time you chat.",
    ["说明"] = "About",
    ["说明正文"] = "Reading Buddy is an AI reading friend that only knows what you've read.\n\n- Long-press to highlight a line, then tap \"Rant\" or \"Ask\".\n- Or open \"Reading Buddy > Open chat\". You can send without typing.\n- Only text before your furthest-read position is sent to your AI provider. Earlier parts are sent as short summaries, which are cached in this book's sidecar (.sdr) folder.\n- Your API key is saved as plain text in KOReader's settings.reader.lua on this device.\n- Needs Wi-Fi.",
    ["未知"] = "unknown",
    ["聊聊"] = "Chat",
    ["跟%s聊聊"] = "Chat with %s",
    ["聊天记录"] = "History",
    ["页面右下角显示陪读小人头"] = "Show buddy icon in the bottom-right corner",
    ["这人是谁来着？"] = "Who's this again?",
    ["这页这个人是谁来着？前面出现过吗？"] = "Who is this person on this page again? Did they show up earlier?",
    ["前面发生了啥？"] = "Recap please",
    ["帮我简单回顾一下前面发生了什么。"] = "Give me a quick recap of what's happened so far.",
    ["气死我了！"] = "So annoying!",
    ["这一段看得我好气，你说说！"] = "This part is making me so mad. Say something!",
    ["你怎么看？"] = "Thoughts?",
    ["读到这儿你怎么看？"] = "What do you think so far?",
    ["从文件读取"] = "From file",
    ["没找到 %s\n\n在电脑上新建一个纯文本文件，里面只写 API Key，文件名叫 readingbuddy-key.txt，用数据线拷进阅读器的 koreader 文件夹（Kobo 是 .adds/koreader），再点一次「从文件读取」。"] = "Couldn't find %s\n\nOn your computer, create a plain text file containing only the API key, name it readingbuddy-key.txt, copy it into the koreader folder on your reader (on Kobo: .adds/koreader), then tap \"From file\" again.",
    ["文件是空的，请在里面写上 API Key。"] = "The file is empty. Please put your API key in it.",
    ["已读取 %s 的 API Key。\n\n为了安全，要把阅读器里的 readingbuddy-key.txt 删掉吗？（Key 已经存进设置了）"] = "API key for %s loaded.\n\nFor safety, delete readingbuddy-key.txt from the reader? (The key is already saved in settings.)",
    ["删掉文件"] = "Delete file",
    ["先留着"] = "Keep it",
    ["第 %d 页"] = "page %d",
    ["开篇"] = "Opening",

    -- 错误
    ["还没设置 AI：请到「Reading Buddy › AI 设置」里选择服务商、填写 API Key 和模型。"] = "AI isn't set up yet: go to \"Reading Buddy > AI settings\" to choose a provider, API key and model.",
    ["API Key 无效或没有权限，请检查设置。"] = "The API key is invalid or lacks permission. Please check Settings.",
    ["找不到这个模型或接口地址，请检查设置里的模型名和地址。（%s）"] = "Model or API URL not found. Please check the model name and URL in Settings. (%s)",
    ["请求太频繁或额度不足，请稍后再试。"] = "Too many requests or out of credit. Please try again later.",
    ["AI 服务出错（%s）：%s"] = "AI service error (%s): %s",
    ["AI 没有回答这个问题，换个说法再试试。"] = "The AI didn't answer that. Try asking another way.",
    ["AI 没有返回内容，请重试。"] = "The AI returned nothing. Please try again.",
    ["连不上 AI 服务：%s"] = "Couldn't reach the AI service: %s",
    ["接口地址格式不对"] = "The API URL looks wrong",

    -- 服务商
    ["Claude（Anthropic）"] = "Claude (Anthropic)",
    ["ChatGPT（OpenAI）"] = "ChatGPT (OpenAI)",
    ["Gemini（Google）"] = "Gemini (Google)",
    ["通义千问（阿里云百炼）"] = "Qwen (Alibaba Cloud)",
    ["Kimi（月之暗面）"] = "Kimi (Moonshot)",
    ["智谱 GLM"] = "Zhipu GLM",
    ["豆包（火山方舟）"] = "Doubao (Volcano Ark)",
    ["OpenRouter（多家模型聚合）"] = "OpenRouter (many models)",
    ["其他（兼容 OpenAI 格式的接口）"] = "Other (OpenAI-compatible API)",
    ["模型名填火山方舟控制台里的模型 ID 或接入点 ID。"] = "Use the model ID or endpoint ID from the Volcano Ark console as the model name.",
    ["点「获取模型列表」可以选几百个模型。"] = "Tap \"Fetch models\" to pick from hundreds of models.",
    ["填写服务商提供的接口地址（一般以 /v1 结尾）和模型名。大多数国内外服务商都兼容这种格式，也可以连同一个 Wi-Fi 下电脑上的本地模型（比如 Ollama）。"] = "Enter the provider's API address (usually ending in /v1) and model name. Most providers support this format. You can also connect to a local model on a computer on the same Wi-Fi (e.g. Ollama).",
}

local M = {}

function M.isChinese()
    local lang = G_reader_settings and G_reader_settings:readSetting("language") or _.current_lang or ""
    return type(lang) == "string" and lang:sub(1, 2) == "zh"
end

--- L("中文", ...)：中文界面返回中文，否则返回英文；有参数时用 string.format 填进去
function M.L(s, ...)
    local out = s
    if not M.isChinese() then out = EN[s] or s end
    if select("#", ...) > 0 then out = string.format(out, ...) end
    return out
end

return M
