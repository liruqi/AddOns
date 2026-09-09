-- 忽略名单一律小写，匹配前按钮名也会转小写；在原有基础上合并了 pfUI addonbuttons 的全部排除项
local IgnoredButtonPatterns = {"jquest", "naut_", "minimapicon", "gathermatepin", "westpointer", "chinchilla_", "smartminimapzoom", "questienote", "smm", "pfminimappin", "pfminimapbutton", "gathernote", "mininotepoi", "fwgminimappoi", "reciperadarminimapicon", "minimaptracking", "cartographernotespoi", "minimapzoomin", "minimapzoomout", "battlefield"}

-- 展开方向配置：面板锚点、按钮网格起点与步进方向、背景渐变、需要隐藏的远端边框
local Directions = {
    LEFT = {
        key = "LEFT",
        point = "RIGHT", relPoint = "LEFT", x = -4, y = 0,
        gridAnchor = "TOPRIGHT", stepX = -1, stepY = -1,
        gradient = "HORIZONTAL", alpha1 = 0, alpha2 = 0.7,
        hideBorder = "left",
    },
    RIGHT = {
        key = "RIGHT",
        point = "LEFT", relPoint = "RIGHT", x = 4, y = 0,
        gridAnchor = "TOPLEFT", stepX = 1, stepY = -1,
        gradient = "HORIZONTAL", alpha1 = 0.7, alpha2 = 0,
        hideBorder = "right",
    },
    TOP = {
        key = "TOP",
        point = "BOTTOM", relPoint = "TOP", x = 0, y = 4,
        gridAnchor = "BOTTOMLEFT", stepX = 1, stepY = 1,
        gradient = "VERTICAL", alpha1 = 0, alpha2 = 0.7,
        hideBorder = "top",
    },
    BOTTOM = {
        key = "BOTTOM",
        point = "TOP", relPoint = "BOTTOM", x = 0, y = -4,
        gridAnchor = "TOPLEFT", stepX = 1, stepY = -1,
        gradient = "VERTICAL", alpha1 = 0.7, alpha2 = 0,
        hideBorder = "bottom",
    },
}

-- 取当前展开方向配置（存档缺失或取值非法时回退到默认的向左）
local function GetDirection()
    local key = MinimapButtonCollectorDB and MinimapButtonCollectorDB.direction or "LEFT"
    return Directions[key] or Directions.LEFT
end

function KillFrame(frame)
    if not frame then return end
    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    if frame.Hide then frame:Hide() end
    if frame.SetParent then frame:SetParent(UIParent) end
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetScript and pcall then
        pcall(frame.SetScript, frame, "OnEvent", nil)
        pcall(frame.SetScript, frame, "OnUpdate", nil)
        pcall(frame.SetScript, frame, "OnDragStart", nil)
        pcall(frame.SetScript, frame, "OnDragStop", nil)
        pcall(frame.SetScript, frame, "OnClick", nil)
        pcall(frame.SetScript, frame, "OnMouseDown", nil)
        pcall(frame.SetScript, frame, "OnMouseUp", nil)
    end
end

MinimapButtonCollector = {collector = nil, toggleButton = nil, dragStartIndex = nil, buttonOrder = {}, currentLayout = {}}

-- 按钮尺寸参数：调整这两个值可整体放大/缩小收纳盒里的图标
-- BUTTON_SIZE 为每个按钮统一缩放到的目标尺寸；CELL_SIZE 为格子间距（含按钮间留白）
local BUTTON_SIZE = 30
local CELL_SIZE = 34

local Setup = {buttonOrder = {}, currentLayout = {}}

function Setup:CalculateLayout(totalButtons)
    if totalButtons <= 20 then
        return 2, math.ceil(totalButtons / 2)
    else
        return 3, math.ceil(totalButtons / 3)
    end
end

function Setup:GetCurrentIndex(button)
    for i, btn in ipairs(self.buttonOrder) do
        if btn == button then return i end
    end
    return nil
end

function Setup:CleanupFrames()
    KillFrame(_G.MBB_MinimapButtonFrame)
    KillFrame(_G.MinimapButtonFrame)
    KillFrame(_G.MBFMiniButtonFrame)
end

-- 面板锚点与背景渐变统一交给 ApplyDirection 处理，这里只建框体和背景
function Setup:CollectorFrame()
    self.collector = CreateFrame("Frame", "MinimapButtonCollectorPanel", UIParent)
    self.collector:SetFrameStrata("MEDIUM")
    self.collector:SetWidth(40)
    self.collector:SetHeight(150)

    self.collector.bg = self.collector:CreateTexture(nil, "BACKGROUND")
    self.collector.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.collector.bg:SetAllPoints()
end

function Setup:IsValidButton(frame)
    if not frame:GetName() or not frame:IsVisible() then return false end
    -- 上限 48：XyTracker 放大档为 44px，需要在收纳范围内
    if frame:GetHeight() > 48 or frame:GetWidth() > 48 then return false end
    if not frame:IsObjectType("Button") and not frame:IsObjectType("Frame") then return false end

    local name = string.lower(frame:GetName())
    for _, pattern in ipairs(IgnoredButtonPatterns) do
        if string.find(name, pattern) then return false end
    end

    if frame:IsObjectType("Button") then
        return frame:GetScript("OnClick") or frame:GetScript("OnMouseDown") or frame:GetScript("OnMouseUp")
    else
        if (string.find(name, "icon") or string.find(name, "button")) and (frame:GetScript("OnMouseDown") or frame:GetScript("OnMouseUp")) then
            return true
        end
        local children = {frame:GetChildren()}
        for _, child in ipairs(children) do
            if child and child:IsObjectType("Button") then return true end
        end
    end
    return false
end

-- 参考 pfUI：扫 Minimap 和 MinimapBackdrop，且下钻两层，避免漏掉嵌套按钮
function Setup:FindButtons()
    local buttons = {}

    local function Scan(parent)
        if not parent then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child ~= Minimap and child ~= MinimapBackdrop then
                if self:IsValidButton(child) then
                    tinsert(buttons, child)
                elseif child.GetNumChildren and child:GetNumChildren() > 0 then
                    for _, sub in ipairs({child:GetChildren()}) do
                        if self:IsValidButton(sub) then tinsert(buttons, sub) end
                    end
                end
            end
        end
    end

    Scan(Minimap)
    Scan(MinimapBackdrop)
    return buttons
end

-- 参考 pfUI：按钮按 CENTER 锚到格子中心，并统一缩放到 BUTTON_SIZE，尺寸不一也能对齐
-- 网格起点与横纵步进方向由展开方向决定
function Setup:PlaceButton(button, index)
    local d = GetDirection()
    local buttonsPerRow = self.currentLayout.buttonsPerRow or 10
    local row = math.floor((index - 1) / buttonsPerRow)
    local col = (index - 1) - (row * buttonsPerRow)
    local x = (15 + col * CELL_SIZE) * d.stepX
    local y = (18 + row * CELL_SIZE) * d.stepY

    local size = math.max(button:GetWidth(), button:GetHeight(), 1)
    local scale = BUTTON_SIZE / size
    if scale > 1 then scale = 1 end
    button:SetScale(scale)

    button:ClearAllPoints()
    button.originalSetPoint(button, "CENTER", self.collector, d.gridAnchor, x / scale, y / scale)
end

function Setup:Collect(button)
    tinsert(self.buttonOrder, button)
    button:SetParent(self.collector)
    button:SetFrameStrata("HIGH")

    if not button.originalSetPoint then
        button.originalSetPoint = button.SetPoint
        button.SetPoint = function() end
    end

    self:EnableDrag(button)
end

function Setup:ScanAndCollect()
    for _, button in ipairs(self:FindButtons()) do
        if not self:GetCurrentIndex(button) then
            self:Collect(button)
        end
    end

    local total = getn(self.buttonOrder)
    if total == 0 then
        self.collector:Hide()
        MinimapButtonCollector.toggleButton:Hide()
        self:UpdateToggleTexture(false)
        return
    end

    MinimapButtonCollector.toggleButton:Show()
    self:RepositionAllButtons()

    if not self.initialArrange then
        self.initialArrange = true
        self.collector:Hide()
    end
    -- 面板可见性可能变化（如初次自动收起），同步 +/- 图标
    self:UpdateToggleTexture()
end

function Setup:RepositionAllButtons()
    local total = getn(self.buttonOrder)
    if total == 0 then return end

    local rows, buttonsPerRow = self:CalculateLayout(total)
    self.collector:SetWidth(42 + (buttonsPerRow * CELL_SIZE))
    self.collector:SetHeight(math.max(30, 12 + (rows * CELL_SIZE)))
    self.currentLayout.buttonsPerRow = buttonsPerRow

    for i, button in ipairs(self.buttonOrder) do
        self:PlaceButton(button, i)
    end
end

-- 四条边一次建齐：上下为横线、左右为竖线，显示哪三条、渐变朝哪边由 ApplyDirection 决定
function Setup:AddBorders()
    local defs = {
        top = {p1 = "BOTTOMLEFT", r1 = "TOPLEFT", p2 = "BOTTOMRIGHT", r2 = "TOPRIGHT", h = 1},
        bottom = {p1 = "TOPLEFT", r1 = "BOTTOMLEFT", p2 = "TOPRIGHT", r2 = "BOTTOMRIGHT", h = 1},
        left = {p1 = "TOPRIGHT", r1 = "TOPLEFT", p2 = "BOTTOMRIGHT", r2 = "BOTTOMLEFT", w = 1},
        right = {p1 = "TOPLEFT", r1 = "TOPRIGHT", p2 = "BOTTOMLEFT", r2 = "BOTTOMRIGHT", w = 1},
    }

    self.borders = {}
    for name, d in pairs(defs) do
        local border = self.collector:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\WHITE8X8")
        border:SetPoint(d.p1, self.collector, d.r1, 0, 0)
        border:SetPoint(d.p2, self.collector, d.r2, 0, 0)
        if d.w then border:SetWidth(d.w) end
        if d.h then border:SetHeight(d.h) end
        border:SetVertexColor(0, 1, 0, 1)
        self.borders[name] = border
    end
end

-- 应用展开方向：重锚面板、设置背景渐变、调整边框显隐与渐变、重排按钮
function Setup:ApplyDirection()
    local d = GetDirection()
    -- 面板吸附在开关按钮（插件图标）上，图标拖到哪里面板就跟到哪里
    local anchor = MinimapButtonCollector.toggleButton
    if anchor then
        self.collector:ClearAllPoints()
        self.collector:SetPoint(d.point, anchor, d.relPoint, d.x, d.y)
    end
    self.collector.bg:SetGradientAlpha(d.gradient, 0.1, 0.1, 0.1, d.alpha1, 0.1, 0.1, 0.1, d.alpha2)

    -- 横边沿水平、竖边沿垂直朝远端淡出；远端那条边隐藏，形成开口朝向开关按钮的效果
    local dir = d.key
    local h1, h2, v1, v2 = 1, 1, 1, 1
    if dir == "LEFT" then
        h1, h2 = 0, 1
    elseif dir == "RIGHT" then
        h1, h2 = 1, 0
    elseif dir == "TOP" then
        v1, v2 = 0, 1
    elseif dir == "BOTTOM" then
        v1, v2 = 1, 0
    end
    self.borders.top:SetGradientAlpha("HORIZONTAL", 0, 1, 0, h1, 0, 1, 0, h2)
    self.borders.bottom:SetGradientAlpha("HORIZONTAL", 0, 1, 0, h1, 0, 1, 0, h2)
    self.borders.left:SetGradientAlpha("VERTICAL", 0, 1, 0, v1, 0, 1, 0, v2)
    self.borders.right:SetGradientAlpha("VERTICAL", 0, 1, 0, v1, 0, 1, 0, v2)
    for name, border in pairs(self.borders) do
        if name == d.hideBorder then border:Hide() else border:Show() end
    end

    self:RepositionAllButtons()
end

function Setup:CreateToggleButton()
    local toggleButton = CreateFrame("Button", "MinimapButtonCollectorToggle", UIParent)
    toggleButton:SetWidth(20)
    toggleButton:SetHeight(20)
    toggleButton:SetClampedToScreen(true)
    toggleButton:SetMovable(true)
    toggleButton:RegisterForDrag("LeftButton")
    toggleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- 拖动保存过的位置优先，否则贴回小地图左侧默认位
    if MinimapButtonCollectorDB.posX and MinimapButtonCollectorDB.posY then
        toggleButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", MinimapButtonCollectorDB.posX, MinimapButtonCollectorDB.posY)
    else
        toggleButton:SetPoint("RIGHT", Minimap, "LEFT", 0, -66)
    end

    -- 未锁定时可左键拖动开关按钮
    toggleButton:SetScript("OnDragStart", function()
        if MinimapButtonCollectorDB.locked then return end
        this:StartMoving()
        this.wasDragged = true
    end)

    toggleButton:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        -- 记录新坐标，重载界面后恢复
        local x, y = this:GetLeft(), this:GetBottom()
        if x and y then
            MinimapButtonCollectorDB.posX = x
            MinimapButtonCollectorDB.posY = y
        end
    end)

    -- 每次按下先清掉旧拖拽标记，避免拖出按钮外释放后吞掉下一次点击
    toggleButton:SetScript("OnMouseDown", function()
        this.wasDragged = false
    end)

    toggleButton:SetScript("OnClick", function()
        -- 右键打开设置面板
        if arg1 == "RightButton" then
            MinimapButtonCollector:ToggleOptions()
            return
        end
        -- 拖动结束时的这次松开不算点击，避免拖完误触开合
        if this.wasDragged then
            this.wasDragged = false
            return
        end
        if self.collector:IsVisible() then
            UIFrameFadeOut(self.collector, 0.3, 1, 0)
            self.collector.fadeInfo.finishedFunc = self.collector.Hide
            self.collector.fadeInfo.finishedArg1 = self.collector
            self:UpdateToggleTexture(false)
        else
            self.collector:SetAlpha(0)
            self.collector:Show()
            UIFrameFadeIn(self.collector, 0.3, 0, 1)
            self:UpdateToggleTexture(true)
        end
    end)

    MinimapButtonCollector.toggleButton = toggleButton
    self:UpdateToggleTexture()
end

-- 展开显示减号（点击收起），收起显示加号（点击展开）
-- expanded 传 nil 时按面板当前可见性自动判断
function Setup:UpdateToggleTexture(expanded)
    local tb = MinimapButtonCollector.toggleButton
    if not tb then return end
    if expanded == nil then
        expanded = self.collector and self.collector:IsVisible()
    end
    if expanded then
        tb:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        tb:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
end

-- 参考 pfUI：持续低频重扫（3 秒），接住晚创建的按钮；挂在常驻框架上，面板隐藏也能扫
function Setup:StartScanner()
    local elapsed = 2.5
    MinimapButtonCollector.frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < 3 then return end
        elapsed = 0
        self:ScanAndCollect()
    end)
end

function Setup:FindDropPosition(button)
    if not self.buttonOrder or getn(self.buttonOrder) == 0 then return 1 end

    local d = GetDirection()
    local buttonsPerRow = self.currentLayout.buttonsPerRow or 10
    local bx, by = button:GetCenter()
    if not bx then return 1 end

    -- 以网格起点角为原点，按方向步进换算行列
    local ox, oy
    if d.gridAnchor == "TOPRIGHT" then
        ox, oy = self.collector:GetRight(), self.collector:GetTop()
    elseif d.gridAnchor == "BOTTOMLEFT" then
        ox, oy = self.collector:GetLeft(), self.collector:GetBottom()
    else
        ox, oy = self.collector:GetLeft(), self.collector:GetTop()
    end
    if not ox then return 1 end

    local relX = (bx - ox) * d.stepX
    local relY = (by - oy) * d.stepY
    local col = math.max(0, math.floor((relX + 3) / CELL_SIZE))
    local row = math.max(0, math.floor((relY + 6) / CELL_SIZE))
    local pos = (row * buttonsPerRow) + col + 1
    return math.min(pos, getn(self.buttonOrder))
end

function Setup:SnapBack(button)
    local left, right, top, bottom = self.collector:GetLeft(), self.collector:GetRight(), self.collector:GetTop(), self.collector:GetBottom()
    local bx, by = button:GetLeft(), button:GetBottom()
    return bx < left or bx > right or by < bottom or by > top
end

function Setup:ReorderButtons(fromIndex, toIndex)
    if fromIndex == toIndex then
        self:RepositionAllButtons()
        return
    end
    local temp = self.buttonOrder[fromIndex]
    tremove(self.buttonOrder, fromIndex)
    tinsert(self.buttonOrder, toIndex, temp)
    self:RepositionAllButtons()
end

function Setup:EnableDrag(button)
    local dragTarget = button
    if button:IsObjectType("Frame") then
        local children = {button:GetChildren()}
        for _, child in ipairs(children) do
            if child:IsObjectType("Button") then
                dragTarget = child
                break
            end
        end
    end

    dragTarget:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    dragTarget:EnableMouse(true)

    dragTarget:SetScript("OnDragStart", function()
        self.dragStartIndex = self:GetCurrentIndex(button)
        if self.dragStartIndex then
            button:StartMoving()
        end
    end)

    dragTarget:SetScript("OnDragStop", function()
        button:StopMovingOrSizing()
        local startIndex = self.dragStartIndex
        self.dragStartIndex = nil
        if not startIndex then return end

        if self:SnapBack(button) then
            self:PlaceButton(button, startIndex)
            return
        end

        self:ReorderButtons(startIndex, self:FindDropPosition(button))
    end)
end

-- 设置面板：展开方向单选、开关按钮锁定、位置重置
function Setup:CreateOptions()
    local panel = CreateFrame("Frame", "MinimapButtonCollectorOptions", UIParent)
    panel:SetWidth(250)
    panel:SetHeight(205)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    })
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() this:StartMoving() end)
    panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    panel:Hide()
    -- 注册进系统特殊框体，按 Esc 可关闭
    tinsert(UISpecialFrames, "MinimapButtonCollectorOptions")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("小地图按钮收藏器设置")

    local dirLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dirLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -42)
    dirLabel:SetText("展开方向")

    -- 四个方向做成单选：点击立即生效并写入存档
    -- 注意：模板自带的 $parentText 在 1.12 下不一定存在，文字标签一律自己建
    local dirNames = {{"LEFT", "向左"}, {"RIGHT", "向右"}, {"TOP", "向上"}, {"BOTTOM", "向下"}}
    panel.dirButtons = {}
    for i, info in ipairs(dirNames) do
        local opt = CreateFrame("CheckButton", "MBCOptDir" .. info[1], panel, "UICheckButtonTemplate")
        opt:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * 54, -58)
        local optLabel = opt:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        optLabel:SetPoint("LEFT", opt, "RIGHT", 2, 0)
        optLabel:SetText(info[2])
        opt.direction = info[1]
        opt:SetScript("OnClick", function()
            MinimapButtonCollectorDB.direction = this.direction
            Setup:RefreshOptions()
            Setup:ApplyDirection()
        end)
        tinsert(panel.dirButtons, opt)
    end

    -- 锁定后开关按钮不可拖动
    local lock = CreateFrame("CheckButton", "MBCOptLock", panel, "UICheckButtonTemplate")
    lock:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -96)
    local lockLabel = lock:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lockLabel:SetPoint("LEFT", lock, "RIGHT", 2, 0)
    lockLabel:SetText("锁定开关按钮（禁止拖动）")
    lock:SetScript("OnClick", function()
        MinimapButtonCollectorDB.locked = this:GetChecked() and true or false
    end)
    panel.lockOption = lock

    -- 把开关按钮恢复到小地图左侧默认位
    local reset = CreateFrame("Button", "MBCOptReset", panel, "UIPanelButtonTemplate")
    reset:SetWidth(130)
    reset:SetHeight(22)
    reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -130)
    reset:SetText("重置开关按钮位置")
    reset:SetScript("OnClick", function()
        MinimapButtonCollectorDB.posX = nil
        MinimapButtonCollectorDB.posY = nil
        local tb = MinimapButtonCollector.toggleButton
        tb:ClearAllPoints()
        tb:SetPoint("RIGHT", Minimap, "LEFT", 0, -66)
    end)

    local hint1 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint1:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -164)
    hint1:SetText("右键点击开关按钮可打开本面板")
    local hint2 = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint2:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -178)
    hint2:SetText("也可以在聊天框输入 /mbc 打开")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)

    self.optionsPanel = panel
end

-- 打开面板前同步一次勾选状态，保证和存档一致
function Setup:RefreshOptions()
    local panel = self.optionsPanel
    if not panel then return end
    -- 1.12 的 SetChecked 只认 1/nil，传布尔值可能直接报错
    for _, opt in ipairs(panel.dirButtons) do
        opt:SetChecked(opt.direction == MinimapButtonCollectorDB.direction and 1 or nil)
    end
    panel.lockOption:SetChecked(MinimapButtonCollectorDB.locked and 1 or nil)
end

function Setup:Run()
    self:CleanupFrames()
    self:CollectorFrame()
    self:AddBorders()
    -- 先建开关按钮，ApplyDirection 才能把面板锚到它上面
    self:CreateToggleButton()
    self:ApplyDirection()
    -- 设置面板创建失败不能拖垮后面的扫描器，错误打到聊天框方便反馈
    local ok, err = pcall(function() self:CreateOptions() end)
    if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("小地图按钮收藏器：设置面板创建失败 - " .. tostring(err))
    end
    self:StartScanner()

    MinimapButtonCollector.collector = self.collector
    MinimapButtonCollector.buttonOrder = self.buttonOrder
end

function MinimapButtonCollector:ToggleOptions()
    local panel = Setup.optionsPanel
    if not panel then return end
    if panel:IsVisible() then
        panel:Hide()
    else
        Setup:RefreshOptions()
        panel:Show()
    end
end

-- 聊天框输入 /mbc 开关设置面板
SLASH_MINIMAPBUTTONCOLLECTOR1 = "/mbc"
SlashCmdList["MINIMAPBUTTONCOLLECTOR"] = function(msg)
    MinimapButtonCollector:ToggleOptions()
end

MinimapButtonCollector.frame = CreateFrame("Frame", nil, UIParent)
MinimapButtonCollector.frame:RegisterEvent("ADDON_LOADED")
MinimapButtonCollector.frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "MinimapButtonCollector" then
        if MinimapButtonCollector.initialized then return end
        -- 初始化持久化配置（toc 里声明的 SavedVariables）
        if not MinimapButtonCollectorDB then MinimapButtonCollectorDB = {} end
        if not MinimapButtonCollectorDB.direction then MinimapButtonCollectorDB.direction = "LEFT" end
        if MinimapButtonCollectorDB.locked == nil then MinimapButtonCollectorDB.locked = false end
        Setup:Run()
        MinimapButtonCollector.initialized = true
    end
end)
