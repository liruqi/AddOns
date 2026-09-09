-- 由Sunelegy基于乌龟魔兽版本定制
if(GetLocale()=="zhCN") then
	MAILTO_TOOLTIP =    "点击选择收件人";
	MAILTO_LISTFULL =   "警告:收件人列表已满";
	MAILTO_ADDED =      "添加到收件人列表";
	MAILTO_REMOVED =    "从收件人列表中移除";
	MAILTO_F_ADD =      "(添加 %s)";
	MAILTO_F_REMOVE =   "(移除 %s)";
else
	MAILTO_TOOLTIP =    "Click to select recipient."
	MAILTO_LISTFULL =   "Warning: List is full!"
	MAILTO_ADDED =      " added to MailTo list."
	MAILTO_REMOVED =    " removed from MailTo list."
	MAILTO_F_ADD =      "(Add %s)"
	MAILTO_F_REMOVE =   "(Remove %s)"
end

local MailTo_Selected, MailTo_Name, MailTo_SavedName, Server
S_MailTo_List = {}

-- 选择收件人
function MailTo_ListSelect()
    local value = this.value
    if value then
      MailTo_SavedName = S_MailTo_List[Server][value]
      _G.Mail_To = nil  -- 清空 Mail_To 变量
      SendMailNameEditBox:SetText(MailTo_SavedName)
      SendMailNameEditBox:HighlightText(0, -1)
      SendMailSubjectEditBox:SetFocus()
    end
end

-- 增加收件人
function MailTo_ListAdd(name)
    if not name then name = MailTo_Name end
    tinsert(S_MailTo_List[Server], name)
    sort(S_MailTo_List[Server])
    print("|cff00FAFA"..name..MAILTO_ADDED)
end

-- 移除收件人
function MailTo_ListRemove()
    tremove(S_MailTo_List[Server], MailTo_Selected)
    print("|cff00FAFA"..MailTo_Name..MAILTO_REMOVED)
end

-- 获取收件人姓名
function MailTo_InList(MCname)
    local LCname = string.lower(MCname)
    for key, name in S_MailTo_List[Server] do
      if LCname == string.lower(name) then return key end
    end
end

-- 下拉菜单
function MailTo_ToList_Init()
    -- 兜底：确保 Server 与收件人列表已初始化（防止 OnEvent 未触发时 nil 报错）
    if not Server then
        Server = GetRealmName()
    end
    if not S_MailTo_List[Server] then
        S_MailTo_List[Server] = {}
    end

    local info = {value = 0, notCheckable = 1}
    MailTo_Name = SendMailNameEditBox:GetText()
    if MailTo_Name ~= "" then
		MailTo_Selected = MailTo_InList(MailTo_Name)
		if MailTo_Selected then
			info.text = string.format(MAILTO_F_REMOVE, MailTo_Name)
			info.func = MailTo_ListRemove
		elseif table.getn(S_MailTo_List[Server]) < UIDROPDOWNMENU_MAXBUTTONS then
			info.text = string.format(MAILTO_F_ADD, MailTo_Name)
			info.func = MailTo_ListAdd
		else
			info = nil
			print("|cffff4040"..MAILTO_LISTFULL)
		end
		if info then UIDropDownMenu_AddButton(info) end
    end
    for key, name in S_MailTo_List[Server] do
      info = {text = name, value = key, func = MailTo_ListSelect}
      if key == MailTo_Selected then info.checked = 1 end
      UIDropDownMenu_AddButton(info)
    end
end

--创建下拉按钮（标准 UIDropDownMenu，便于 pfUI SkinDropDown 美化）
local MailToDropDownMenu = CreateFrame("Button", "MailToDropDownMenu", SendMailNameEditBox, "UIDropDownMenuTemplate")
    local xOffset
    if pfUI and pfUI.env then
        xOffset = 34
    else
        xOffset = -10
    end
MailToDropDownMenu:Show()
UIDropDownMenu_SetWidth(24, MailToDropDownMenu)
MailToDropDownMenu:SetPoint("RIGHT", SendMailNameEditBox, "RIGHT", xOffset, -3)

-- 下拉列表弹出位置（锚定收件人输入框右下方）
MailToDropDownMenu.point = "TOPRIGHT"
MailToDropDownMenu.relativeTo = SendMailNameEditBox
MailToDropDownMenu.relativePoint = "BOTTOMRIGHT"
MailToDropDownMenu.xOffset = 0
MailToDropDownMenu.yOffset = 0
UIDropDownMenu_Initialize(MailToDropDownMenu, MailTo_ToList_Init, "MENU")

-- 点击下拉按钮切换列表
MailToDropDownMenuButton:SetScript("OnClick", function()
	ToggleDropDownMenu(1, nil, MailToDropDownMenu)
	PlaySound("igMainMenuOptionCheckBoxOn")
end)

-- 鼠标提示
MailToDropDownMenuButton:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this,"ANCHOR_TOPRIGHT")
	GameTooltip:SetText(MAILTO_TOOLTIP)
	GameTooltip:Show()
end)

MailToDropDownMenuButton:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- 关闭时收起菜单
MailToDropDownMenu:SetScript("OnHide", function()
	CloseDropDownMenus()
end)

MailToDropDownMenu:RegisterEvent("VARIABLES_LOADED");
MailToDropDownMenu:SetScript("OnEvent", function()
    Server = GetRealmName()

    if not S_MailTo_List[Server] then
		S_MailTo_List[Server]={}
	end

    MailToDropDownMenu.displayMode = "MENU"
end)