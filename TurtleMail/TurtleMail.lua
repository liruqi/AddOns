TurtleMail = TurtleMail or {}
L = TurtleMail.L

local m = TurtleMail

local function get_realm_faction_key()
  local realm = "UnknownRealm"
  if m.api and m.api.GetCVar then
    local ok, r = pcall(m.api.GetCVar, "realmName")
    if ok and r and r ~= "" then realm = r end
  end

  local faction = "Unknown"
  if m.api and m.api.UnitFactionGroup then
    local ok2, f = pcall(m.api.UnitFactionGroup, "player")
    if ok2 and f and f ~= "" then faction = f end
  end

  return realm .. "|" .. faction
end

-- Optional: expose via m for convenience
m.get_realm_faction_key = get_realm_faction_key

local getn = table.getn 
local function pack( ... ) return arg end

local ATTACHMENTS_MAX = 21
local ATTACHMENTS_PER_ROW_SEND = 7
local ATTACHMENTS_MAX_ROWS_SEND = 3

local TurtleMail_SelectedItems = {} 
local selected = {} 

local INBOX_AUCTIONHOUSES = {
  [ "Stormwind Auction House" ] = true,
  [ "Alliance Auction House" ] = true,
  [ "Darnassus Auction House" ] = true,
  [ "Undercity Auction House" ] = true,
  [ "Thunder Bluff  Auction House" ] = true,
  [ "Horde Auction House" ] = true,
  [ "Blackwater Auction House" ] = true,
}

TurtleMail.api = getfenv()
TurtleMail.timer = 0
TurtleMail.log = {}
TurtleMail.orig = {}
TurtleMail.hooks = {}
TurtleMail.hook = setmetatable( {}, { __newindex = function( _, k, v ) m.hooks[ k ] = v end } )
TurtleMail.debug_enabled = false

---@type Calendar
TurtleMail.calendar = m.Calendar.new()

function TurtleMail:init()
  self.debug( "TurtleMail.init" )
  self.update_frame = m.api.CreateFrame( "Frame", "TurtleMailFrame", m.api.MailFrame )
  self.update_frame:SetScript( "OnUpdate", self.on_update )

  -- Register events
  self.update_frame:SetScript( "OnEvent", function() self[ event ]() end )
  for _, event in { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } do
    self.update_frame:RegisterEvent( event )
  end

  -- Set default log settings
  m.api.TurtleMail_Log = {
    Sent = {},
    Received = {},
    Settings = {
      Enabled = false,
      SentFilters = { Money = 1, COD = 1, Other = 1 },
      ReceivedFilters = { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }
    }
  }
  m.api.TurtleMail_AutoCompleteNames = {}

  -- hack to prevent beancounter from deleting mail
  self.TakeInboxMoney, self.TakeInboxItem, self.DeleteInboxItem = m.api.TakeInboxMoney, m.api.TakeInboxItem, m.api.DeleteInboxItem

  self.tooltip_frame = m.api.CreateFrame( "GameTooltip", "TurtleMailTooltipFrame", nil, "GameTooltipTemplate" )
  self.tooltip_frame:SetOwner( m.api.WorldFrame, "ANCHOR_NONE" );
end

---@param args string
function TurtleMail.slash_command( args )
  if args == "" or args == "help" then
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473TurtleMail " .. L[ "Help" ] .. "|r" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm log|r " .. L[ "Toggle logging on/off" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear sent|r " .. L[ "Clear sent log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear received|r " .. L[ "Clear received log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear names|r " .. L[ "Clear saved recipient names from autocomplete" ] )
    return
  end

  if args == "log" then
    m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ] = not m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ]
    if m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ] then
      m.info( L[ "Logging is enabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.api.MailFrameTab3:Show()
      end
    else
      m.info( L[ "Logging is disabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.api.MailFrameTab3:Hide()
      end
    end
    m.log_enabled = m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ]
  end

  if string.find( args, "^clear" ) then
    if args == "clear sent" then
      m.info( L[ "Sent log cleared." ] )
      m.api.TurtleMail_Log[ "Sent" ] = {}
    elseif args == "clear received" then
      m.info( L[ "Received log cleared." ] )
      m.api.TurtleMail_Log[ "Received" ] = {}
    elseif args == "clear names" then
      m.info( L[ "Recipient autocomplete names have been cleared." ] )
      local key = get_realm_faction_key()
      m.api.TurtleMail_AutoCompleteNames[ key ] = {}
    end
  end

  if args == "debug" then
    m.debug_enabled = not m.debug_enabled
    if m.debug_enabled then
      m.info( L[ "Debug is enabled." ] )
    else
      m.info( L[ "Debug is disabled." ] )
    end
  end
end

function TurtleMail_selected_time() 
  m.selected_time = m.selected_time - 1
  m.inbox_update = true
end

function TurtleMail.on_update()
  if not m.api.MailFrame or not m.api.MailFrame:IsVisible() then return end

  if m._cursorItem then
    m.debug( "on_update: cursorItem" )
    m.cursorItem = m._cursorItem
    m._cursorItem = nil
  end

  if m.sendmail_update then
    m.debug( "on_update: sendmail" )
    m.sendmail_update = nil
    if m.sendmail_sending then
      m.debug( "m.sendmail_sending" )
      m.sendmail_send()
    end
  end

  if m.inbox_update then
    m.debug( "on_update: inbox_update" )
    m.inbox_update = false
    if not m.Mail_open_Selected then
      local  _, _, _, _, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( m.inbox_index )
      if m.inbox_index > m.api.GetInboxNumItems() then
        if m.money_received > 0 then
          m.info( string.format( "%s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
        end
        m.inbox_abort()
      elseif m.inbox_skip or isGM  or (m.api.TurtleMail_AutoCOD ~= 1 and COD > 0) then
        m.inbox_skip = false
        m.inbox_index = m.inbox_index + 1
        m.inbox_update = true
      else
        m.inbox_open( m.inbox_index )
      end
    else
      if not selected[1] then
        if m.money_received > 0 then
          m.info( string.format( "%s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
        end
	m.money_received = 0
        m.inbox_opening = false
        return
      end
      local  _, _, _, _, money, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( selected[m.inbox_index] )
      
      if isGM or (m.api.TurtleMail_AutoCOD ~= 1 and COD > 0) then
        tremove(selected, 1)
        m.inbox_update = true
      else
        if m.selected_time >0 then
          TurtleMail_selected_time()
        elseif m.selected_time == 0 then
			local idx = selected[1]
			if idx then
			  m.pending_selected_index = idx
			  m.inbox_open(idx)
			end
        end
      end
    end
  end

  if m.timer > 0 then
    m.timer = m.timer - 1
  elseif not m.inbox_opening then
    m.timer = 200
    m.api.CheckInbox()
  end
end

function TurtleMail.CURSOR_UPDATE()
  m.cursorItem = nil
end

function TurtleMail.get_cursor_item()
  return m.cursorItem
end

---@param item table
function TurtleMail.set_cursor_item( item )
  m._cursorItem = item
end

function TurtleMail.BAG_UPDATE()
  if m.api.MailFrame:IsVisible() then
    m.api.SendMailFrame_Update()
  end
end

function TurtleMail.MAIL_SHOW()
  if m.api.TurtleMail_Point then
    m.debug( "Set point" )
    m.api.MailFrame:SetPoint( m.api.TurtleMail_Point.point, m.api.TurtleMail_Point.x, m.api.TurtleMail_Point.y )
  end

  if not m.first_show then
    m.first_show = true
    if m.pfui_skin_enabled then
      m.api.pfUI.api.StripTextures( m.api.SendMailPackageButton )
    end

    local background = ({ m.api.SendMailPackageButton:GetRegions() })[ 1 ]
    background:Hide()
    local count = ({ m.api.SendMailPackageButton:GetRegions() })[ 3 ]
    count:Hide()
    m.api.SendMailPackageButton:Disable()
    m.api.SendMailPackageButton:SetScript( "OnReceiveDrag", nil )
    m.api.SendMailPackageButton:SetScript( "OnDragStart", nil )
  end

  if m.log_enabled then
    m.api.MailFrameTab3:Show()
  else
    m.api.MailFrameTab3:Hide()
  end

  m.timer = 0
  m.money_received = 0
  m.update_money( 0 )
end

function TurtleMail.MAIL_CLOSED()
  m.inbox_abort()
  m.sendmail_sending = false
  m.sendmail_clear()
end

function TurtleMail.UI_ERROR_MESSAGE()
  if m.inbox_opening then
    if arg1 == m.api.ERR_INV_FULL then
      m.inbox_abort()
    elseif arg1 == m.api.ERR_ITEM_MAX_COUNT then
      m.inbox_skip = true
    end
  elseif m.sendmail_sending and (arg1 == m.api.ERR_MAIL_TO_SELF or arg1 == m.api.ERR_PLAYER_WRONG_FACTION or arg1 == m.api.ERR_MAIL_TARGET_NOT_FOUND or arg1 == m.api.ERR_MAIL_REACHED_CAP) then
    m.sendmail_sending = false
    m.sendmail_state = nil
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
  end
end

function TurtleMail.ADDON_LOADED()
  if arg1 ~= "TurtleMail" then return end

  local version = m.api.GetAddOnMetadata( "TurtleMail", "Version" )
  m.info( string.format( "Loaded (|cffeda55fv%s|r).", version ) )

  if not m.api.TurtleMail_Log[ "Settings" ].first_run then
    m.api.TurtleMail_Log[ "Settings" ].first_run = version
    m.info( "New in |cffeda55fv1.4|r: Enable logging with |cffabd473/tm log|r" )
  end

  if m.api.UIPanelWindows[ "MailFrame" ] then
    m.api.UIPanelWindows[ "MailFrame" ].pushable = 1
  else
    m.api.UIPanelWindows[ "MailFrame" ] = { area = "left", pushable = 1 }
  end

  if m.api.UIPanelWindows[ "FriendsFrame" ] then
    m.api.UIPanelWindows[ "FriendsFrame" ].pushable = 2
  else
    m.api.UIPanelWindows[ "FriendsFrame" ] = { area = "left", pushable = 2 }
  end

  m.api.MailFrame:SetScript( "OnDragStop", m.on_drag_stop )
  m.api.MailFrame:SetClampedToScreen( true )
  m.api.PanelTemplates_SetNumTabs( m.api.MailFrame, 3 )

  m.inbox_load()
  m.sendmail_load()
  m.log.load()
  m.pfui_skin()
end

function TurtleMail.PLAYER_LOGIN()
  m.debug( "PLAYER_LOGIN" )
  for k, v in m.hooks do
    m.orig[ k ] = m.api[ k ]
    m.api[ k ] = v
  end
	local key = get_realm_faction_key()
	m.api.TurtleMail_AutoCompleteNames[ key ] = m.api.TurtleMail_AutoCompleteNames[ key ] or {}

	for char, last_seen in pairs( m.api.TurtleMail_AutoCompleteNames[ key ] or {} ) do
	  if m.api.GetTime() - last_seen > 60 * 60 * 24 * 30 then
		m.api.TurtleMail_AutoCompleteNames[ key ][ char ] = nil
	  end
	end

  m.add_auto_complete_name( m.api.UnitName( "player" ) )
  m.log_enabled = m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ]

  SLASH_TURTLEMAIL1 = "/turtlemail"
  SLASH_TURTLEMAIL2 = "/tm"
  m.api.SlashCmdList[ "TURTLEMAIL" ] = m.slash_command
end

function TurtleMail.MAIL_SEND_SUCCESS()
  m.debug( "MAIL_SEND_SUCCESS" )
  if m.sendmail_state and not m.sendmail_state.sent then
    m.sendmail_state.sent = true
    m.log.add( 'Sent', m.sendmail_state )
    m.add_auto_complete_name( m.sendmail_state.to )
  end
  if m.sendmail_sending then
    m.sendmail_update = true
  end
end

function TurtleMail.MAIL_INBOX_UPDATE()
  if m.inbox_opening then
    m.inbox_update = true
  end

  for i = 1, 7 do
    local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
    if index <= m.api.GetInboxNumItems() then
      local _, _, sender, _, _, _, _, _, _, was_returned = m.api.GetInboxHeaderInfo( index )
      if INBOX_AUCTIONHOUSES[ sender ] then
        m.api[ "TurtleMailAuctionIcon" .. i ]:Show()
      else
        m.api[ "TurtleMailAuctionIcon" .. i ]:Hide()
      end
      if was_returned then
        m.api[ "TurtleMailReturnedArrow" .. i ]:Show()
      else
        m.api[ "TurtleMailReturnedArrow" .. i ]:Hide()
      end
    end
  end

--新增选择取件
  for i = 1, 7 do
    local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
    if index > m.api.GetInboxNumItems() then
       getglobal("TurtleMailBoxItem" .. i .. "CB"):Hide()
    else
      getglobal("TurtleMailBoxItem" .. i .. "CB"):Show()
      getglobal("TurtleMailBoxItem" .. i .. "CB"):SetChecked(nil)
		for _, v in ipairs(TurtleMail_SelectedItems) do
		  if v == index then
			getglobal("TurtleMailBoxItem" .. i .. "CB"):SetChecked(1)
			break
		  end
		end
    end
  end
  
	if m.Mail_open_Selected and selected and selected[1] then
	  local cur = m.api.GetInboxNumItems()
	  if m.pending_selected_index then
		if cur < (m.last_inbox_count or cur) then
		  tremove(selected, 1)
		  for i = 1, getn(selected) do
			selected[i] = selected[i] - 1
		  end
		  m.last_inbox_count = cur
		  m.pending_selected_index = nil
		  m.selected_time = 10
		  m.inbox_update = true
		else
		  m.inbox_update = true
		end
	  end
	end
  
end

---@param name string
function TurtleMail.add_auto_complete_name( name )
  local key = get_realm_faction_key()
  m.api.TurtleMail_AutoCompleteNames[ key ] = m.api.TurtleMail_AutoCompleteNames[ key ] or {}
  m.api.TurtleMail_AutoCompleteNames[ key ][ name ] = m.api.GetTime()
end

function TurtleMail.inbox_load()

--新增选择取件
  m.api.InboxFrame:EnableMouse( false )
  local btnAll = m.api.CreateFrame( "Button", "TurtleMailOpenAllMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnAll:SetPoint( "LEFT",m.api.InboxFrame, "TOP", 15, -53 )
  btnAll:SetText("接收所有邮件")
  btnAll:SetWidth(120)
  btnAll:SetHeight( 25 )
  btnAll:SetScript( "OnClick", m.inbox_open_all )

  local btnSelected = m.api.CreateFrame( "Button", "TurtleMailOpenSelectedMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnSelected:SetPoint( "RIGHT",m.api.InboxFrame, "TOP", 5, -53 )
  btnSelected:SetText("接收选择邮件")
  btnSelected:SetWidth(120)
  btnSelected:SetHeight( 25 )
  btnSelected:SetScript( "OnClick", m.inbox_open_selected )

--新增自动到付选项
  local CODCheckButton = m.api.CreateFrame( "CheckButton", "TurtleMailCODCheckButton", m.api.InboxFrame, "OptionsCheckButtonTemplate" )
  CODCheckButton:SetPoint( "TOP",m.api.InboxFrame, "BOTTOM", -25, 115)
  TurtleMailCODCheckButtonText:SetText("自动到付")
  CODCheckButton:SetWidth(24)
  CODCheckButton:SetHeight( 24 )
  CODCheckButton:SetScript( "OnUpdate", function()
    if m.api.TurtleMail_AutoCOD == 1 then
      CODCheckButton:SetChecked(1)
    else
      CODCheckButton:SetChecked(0)
    end
  end)
  CODCheckButton:SetScript( "OnClick", function()
    if m.api.TurtleMail_AutoCOD == 1 then
      m.api.TurtleMail_AutoCOD = 0
    else
      m.api.TurtleMail_AutoCOD = 1
    end
  end)
  CODCheckButton:SetScript( "OnEnter", function()
    GameTooltip:ClearLines();
    GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("警告！！！")
    GameTooltip:AddLine("请仔核对认邮件，否则遭受损失概不负责！")
    GameTooltip:Show()
  end)
  CODCheckButton:SetScript( "OnLeave", function() GameTooltip:Hide() end )

  MailItem1:SetPoint("TOPLEFT", m.api.InboxFrame, "TOPLEFT", 48, -80)
  for i=1,7 do
    getglobal("MailItem" .. i .. "ExpireTime"):SetPoint("TOPRIGHT", "MailItem" .. i, "TOPRIGHT", -15, -4)
    getglobal("MailItem" .. i):SetWidth(280)
  end

  for i = 1, 7 do
    m.api[ "TurtleMailAuctionIcon" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    m.api[ "TurtleMailReturnedArrow" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
  end
end

--新增选择取件
function TurtleMail.inbox_open_all()
  m.inbox_opening = true
  m.inbox_update_lock()
  m.inbox_skip = false
  m.inbox_index = 1
  m.inbox_update = true
  m.Mail_open_Selected = false
end

function TurtleMail_Inbox_SetSelected()
  local id = this:GetID() + (m.api.InboxFrame.pageNum - 1) * 7
    if not this:GetChecked() then
		for k, v in ipairs(TurtleMail_SelectedItems) do
		  if v == id then
			tremove(TurtleMail_SelectedItems, k)
			found = true
			break
		  end
		end
    else
      tinsert(TurtleMail_SelectedItems, id)
    end
end

function TurtleMail.inbox_open_selected()
	if getn(TurtleMail_SelectedItems) == 0 then
	  return
	end

	selected = {}

	local seen = {}
	local total = m.api.GetInboxNumItems()
	for _, i in ipairs(TurtleMail_SelectedItems) do
	  if type(i) == "number" and i >= 1 and i <= total and not seen[i] then
		tinsert(selected, i)
		seen[i] = true
	  end
	end
	sort(selected)

	TurtleMail_SelectedItems = {}

	m.Mail_open_Selected = true
	m.inbox_opening = true
	m.inbox_update_lock()
	m.inbox_skip = false
	m.inbox_index = 1
	m.inbox_update = true
	m.selected_time = 0

	m.last_inbox_count = total
	m.pending_selected_index = nil
end

function TurtleMail.inbox_abort()
  m.inbox_opening = false
  m.inbox_update_lock()
  m.inbox_update = false
end

---Sunelegy修复付款取信报错
function TurtleMail.set_cod_text()
    local text = m.api.COD_AMOUNT or ""

  if not m.pfui_skin_enabled then
    local matched = string.match(text, "^(.-)%s+%S+$")
    if matched then
      text = matched
    end
  end

  text = text or ""

  if m.api.SendMailCODAllButton:GetChecked() then
    m.api.SendMailMoneyText:SetText(L["each mail"] .. " " .. text)-- .. " " .. L["each mail"] .. ":")
  else
    m.api.SendMailMoneyText:SetText(L["1st mail"] .. " " .. text)-- .. " " .. L["1st mail"] .. ":")
  end
end

---@param copper number
function TurtleMail.format_money( copper )
  if type( copper ) ~= "number" then return "-" end

  local gold = math.floor( copper / 10000 )
  local silver = math.floor( (copper - gold * 10000) / 100 )
  local copper_remain = copper - (gold * 10000) - (silver * 100)

  local result = ""
  if gold > 0 then
    result = result .. string.format( "|cffffffff%d|cffffd700金|r ", gold )
  end
  if silver > 0 then
    result = result .. string.format( "|cffffffff%d|cffc7c7cf银|r ", silver )
  end
  if copper_remain > 0 or result == "" then
    result = result .. string.format( "|cffffffff%d|cffeda55f铜|r ", copper_remain )
  end

  return result
end

---@param money number
function TurtleMail.update_money( money )
  m.money_received = m.money_received + money
  m.api.MoneyReceived:SetText( L[ "Money received" ] .. ": " .. m.format_money( m.money_received ) )

  if m.money_received > 0 then
    m.api.MoneyReceived:Show()
  else
    m.api.MoneyReceived:Hide()
  end
end

function TurtleMail.on_drag_stop()
  this:StopMovingOrSizing()
  local point, _, _, x, y = m.api.MailFrame:GetPoint()
  m.api.TurtleMail_Point = { point = point, x = x, y = y }
end

---@param i number
---@param manual boolean?
function TurtleMail.inbox_open( i, manual )
  m.debug( "inbox_open" )
  local package_icon, _, sender, subject, money, cod, _, has_item, read, returned, _, _, gm = m.api.GetInboxHeaderInfo( i )

  if has_item then
    if not m.received_icon then
      m.received_item = m.api.GetInboxItem( i )
      m.received_icon = package_icon
    end
  end

  if (read and not has_item) or manual then
    if money > 0 then
      m.update_money( money )
      m.received_money = money
    end
    if money == 0 or manual then
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = manual and money or m.received_money,
        cod = cod,
        returned = returned,
        gm = gm,
        icon = m.received_icon,
        item = m.received_item
      } )
      m.received_money = 0
      m.received_icon = nil
      m.received_item = nil
    end
  end

  m.api.GetInboxText( i )
  m.TakeInboxMoney( i )
  m.TakeInboxItem( i )
  m.DeleteInboxItem( i )
    
end

function TurtleMail.inbox_update_lock()
  for i = 1, 7 do
    m.api[ "MailItem" .. i .. "ButtonIcon" ]:SetDesaturated( m.inbox_opening )
    if m.inbox_opening then
      m.api[ "MailItem" .. i .. "Button" ]:SetChecked( nil )
    end
  end
end

function TurtleMail.hook.GetInboxHeaderInfo( ... )
  local sender, canReply = arg[ 3 ], arg[ 12 ]
  if sender and canReply then
    m.add_auto_complete_name( sender )
  end

  return m.orig.GetInboxHeaderInfo( unpack( arg ) )
end

function TurtleMail.hook.OpenMail_Reply( ... )
  m.api.TurtleMail_To = nil
  return m.orig.OpenMail_Reply( unpack( arg ) )
end

function TurtleMail.hook.InboxFrame_Update()
  m.orig.InboxFrame_Update()
  for i = 1, 7 do
    -- hack for tooltip update
    m.api[ "MailItem" .. i ]:Hide()
    m.api[ "MailItem" .. i ]:Show()
  end

  local currentPage = m.api.InboxFrame.pageNum
  local totalPages = math.ceil( m.api.GetInboxNumItems() / m.api.INBOXITEMS_TO_DISPLAY )
  local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or m.api.EMPTY
  m.api.InboxTitleText:SetText( m.api.INBOX .. " [" .. text .. "]" )

  m.inbox_update_lock()
end

---@param i number
function TurtleMail.hook.InboxFrame_OnClick( i )
  if m.inbox_opening or arg1 == "RightButton" and (m.api.TurtleMail_AutoCOD ~= 1) and ({ m.api.GetInboxHeaderInfo( i ) })[ 6 ] > 0 then --新增自动到付选项
    this:SetChecked( nil )
  elseif arg1 == "RightButton" then
    m.inbox_open( i, true )
  else
    return m.orig.InboxFrame_OnClick( i )
  end
end

function TurtleMail.hook.InboxFrameItem_OnEnter()
  m.orig.InboxFrameItem_OnEnter()
  if m.api.GetInboxItem( this.index ) then
    m.api.GameTooltip:AddLine( m.api.ITEM_OPENABLE, "", 0, 1, 0 )
    m.api.GameTooltip:Show()
  end
end

function TurtleMail.hook.SendMailFrame_Update()
  local gap
  local last = m.sendmail_num_attachments()

  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]

    local texture, count
    if btn.item then
      texture, count = m.api.GetContainerItemInfo( unpack( btn.item ) )
    end
    if not texture then
      btn:SetNormalTexture( nil )
      m.api[ btn:GetName() .. "Count" ]:Hide()
      btn.item = nil
    else
      btn:SetNormalTexture( texture )
      if count > 1 then
        m.api[ btn:GetName() .. "Count" ]:Show()
        m.api[ btn:GetName() .. "Count" ]:SetText( count )
      else
        m.api[ btn:GetName() .. "Count" ]:Hide()
      end
    end
  end

  if m.sendmail_num_attachments() > 0 then
    m.api.SendMailCODButton:Enable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if m.sendmail_num_attachments() > 1 and m.api.SendMailCODButton:GetChecked() then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    else
      m.api.SendMailCODAllButton:Disable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
      m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    end
  else
    m.api.SendMailSendMoneyButton:SetChecked( 1 )
    m.api.SendMailCODButton:SetChecked( nil )
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    m.api.SendMailCODButton:Disable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  end

  m.api.MoneyFrame_Update( "SendMailCostMoneyFrame", m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) )

  -- Determine how many rows of attachments to show
  local itemRowCount = 1
  local temp = last
  while temp > ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND do
    itemRowCount = itemRowCount + 1
    temp = temp - ATTACHMENTS_PER_ROW_SEND
  end

  if not gap and temp == ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND then
    itemRowCount = itemRowCount + 1
  end
  if m.api.SendMailFrame.maxRowsShown and last > 0 and itemRowCount < m.api.SendMailFrame.maxRowsShown then
    itemRowCount = m.api.SendMailFrame.maxRowsShown
  else
    m.api.SendMailFrame.maxRowsShown = itemRowCount
  end

  -- Compute sizes
  local cursorx = 0
  local cursory = itemRowCount - 1
  local marginxl = 8 + 6
  local marginxr = 40 + 6
  local areax = m.api.SendMailFrame:GetWidth() - marginxl - marginxr
  local iconx = m.api.MailAttachment1:GetWidth() + 2
  local icony = m.api.MailAttachment1:GetHeight() + 2
  local gapx1 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1) )
  local gapx2 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2 )
  local gapy1 = 5
  local gapy2 = 6
  local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount)
  local indentx = marginxl + gapx2 + 17
  local indenty = 170 + gapy2 + icony - 13
  local tabx = (iconx + gapx1) - 3 --this magic number changes the attachment spacing
  local taby = (icony + gapy1)
  local scrollHeight = 249 - areay

  m.api.MailHorizontalBarLeft:SetPoint( "TOPLEFT", m.api.SendMailFrame, "BOTTOMLEFT", 2 + 15, 184 + areay - 14 )

  m.api.SendMailScrollFrame:SetHeight( scrollHeight )
  m.api.SendMailScrollChildFrame:SetHeight( scrollHeight )

  local SendMailScrollFrameTop = ({ m.api.SendMailScrollFrame:GetRegions() })[ 3 ]
  SendMailScrollFrameTop:SetHeight( scrollHeight )
  SendMailScrollFrameTop:SetTexCoord( 0, .484375, 0, scrollHeight / 256 )

  m.api.StationeryBackgroundLeft:SetHeight( scrollHeight )
  m.api.StationeryBackgroundLeft:SetTexCoord( 0, 1, 0, scrollHeight / 256 )


  m.api.StationeryBackgroundRight:SetHeight( scrollHeight )
  m.api.StationeryBackgroundRight:SetTexCoord( 0, 1, 0, scrollHeight / 256 )

  -- Set Items
  for i = 1, ATTACHMENTS_MAX do
    if cursory >= 0 then
      m.api[ "MailAttachment" .. i ]:Enable()
      m.api[ "MailAttachment" .. i ]:Show()
      m.api[ "MailAttachment" .. i ]:SetPoint( "TOPLEFT", "SendMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx),
        indenty + (taby * cursory) )

      cursorx = cursorx + 1
      if cursorx >= ATTACHMENTS_PER_ROW_SEND then
        cursory = cursory - 1
        cursorx = 0
      end
    else
      m.api[ "MailAttachment" .. i ]:Hide()
    end
  end

  m.api.SendMailFrame_CanSend()
end

function TurtleMail.hook.SendMailRadioButton_OnClick( index )
  if (index == 1) then
    m.api.SendMailSendMoneyButton:SetChecked( 1 );
    m.api.SendMailCODButton:SetChecked( nil );
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND );
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  else
    m.api.SendMailSendMoneyButton:SetChecked( nil );
    m.api.SendMailCODButton:SetChecked( 1 );
    m.api.SendMailMoneyText:SetText( m.api.COD_AMOUNT );

    if m.sendmail_num_attachments() > 1 then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    end
  end
  m.api.PlaySound( "igMainMenuOptionCheckBoxOn" );
end

function TurtleMail.hook.ClickSendMailItemButton()
  m.sendmail_set_attachment( m.get_cursor_item() )
end

function TurtleMail.hook.GetContainerItemInfo( bag, slot )
  local ret = pack( m.orig.GetContainerItemInfo( bag, slot ) )
  ret[ 3 ] = ret[ 3 ] or m.sendmail_attached( bag, slot ) and 1 or nil
  return unpack( ret )
end

function TurtleMail.hook.PickupContainerItem( bag, slot )
  -- Alt+Left: add all same items
  if arg1 == "LeftButton" and m.api.IsAltKeyDown() and m.api.MailFrame:IsVisible() then
    local link = m.api.GetContainerItemLink(bag, slot)
    if link then
      local _, _, itemId = string.find(link, "item:(%d+)")
      if itemId then
        itemId = tonumber(itemId)
        -- Iterate through all bags
        for b = 0, 4 do
          local slots = m.api.GetContainerNumSlots(b)
          for s = 1, slots do
            -- Check if attachment slots are full
            if m.sendmail_num_attachments() >= ATTACHMENTS_MAX then
              break
            end
            local l = m.api.GetContainerItemLink(b, s)
            if l then
              local _, _, id = string.find(l, "item:(%d+)")
              if id and tonumber(id) == itemId then
                if not m.sendmail_attached(b, s) then
                  m.sendmail_set_attachment({b, s})
                end
              end
            end
          end
          if m.sendmail_num_attachments() >= ATTACHMENTS_MAX then
            break
          end
        end
      end
    end
    return
  end

  if m.sendmail_attached( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      return m.sendmail_remove_attachment( { bag, slot } )
    end
    return m.orig.PickupContainerItem( bag, slot )
  end

  if m.api.GetContainerItemInfo( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      m.api.MailFrameTab_OnClick( 2 )
      m.sendmail_set_attachment( { bag, slot } )
      return
    else
      m.set_cursor_item( { bag, slot } )
    end
  end
  return m.orig.PickupContainerItem( bag, slot )
end

function TurtleMail.hook.SplitContainerItem( bag, slot, amount )
  if m.sendmail_attached( bag, slot ) then return end
  return m.orig.SplitContainerItem( bag, slot, amount )
end

function TurtleMail.hook.UseContainerItem( bag, slot, onself )
  if m.sendmail_attached( bag, slot ) then return end
  if m.api.IsShiftKeyDown() or m.api.IsControlKeyDown() or m.api.IsAltKeyDown() then
    return m.orig.UseContainerItem( bag, slot, onself )
  elseif m.api.MailFrame:IsVisible() then
    m.api.MailFrameTab_OnClick( 2 )
    m.sendmail_set_attachment( { bag, slot } )
  elseif m.api.TradeFrame:IsVisible() then
    for i = 1, 6 do
      if not m.api.GetTradePlayerItemLink( i ) then
        m.orig.PickupContainerItem( bag, slot )
        m.api.ClickTradeButton( i )
        return
      end
    end
  else
    return m.orig.UseContainerItem( bag, slot, onself )
  end
end

function TurtleMail.hook.SendMailFrame_CanSend()
  if not m.sendmail_sending and string.len( m.api.SendMailNameEditBox:GetText() ) > 0 and (m.api.SendMailSendMoneyButton:GetChecked() and m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ) or 0) + m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) <= m.api.GetMoney() then
    MailMailButton:Enable()
  else
    MailMailButton:Disable()
  end
end

function TurtleMail.hook.MailFrameTab_OnClick( tab )
  if not tab then
    tab = this:GetID()
  end

  if tab == 3 then
    m.api.PanelTemplates_SetTab( m.api.MailFrame, 3 )
    m.api.InboxFrame:Hide()
    m.api.SendMailFrame:Hide()
    m.api.TurtleMailLogFrame:Show()
    m.api.MailFrameTopLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft" )
    m.api.MailFrameTopRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight" )
    m.api.MailFrameBotLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotLeft" )
    m.api.MailFrameBotRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight" )
    m.api.MailFrameTopLeft:SetPoint( "TOPLEFT", "MailFrame", "TOPLEFT", 2, -1 )
    m.log.populate( "Received" )
    return
  else
    m.api.TurtleMailLogFrame:Hide()
  end

  m.orig.MailFrameTab_OnClick( tab )
end

function TurtleMail.hook.OpenMailFrame_OnHide()
  if m.api.InboxFrame.openMailID then
    local package_icon, _, sender, subject, money, cod, _, itemID, _, returned, text_created, _, gm = m.api.GetInboxHeaderInfo( m.api.InboxFrame.openMailID )
    if (money == 0 and not itemID and text_created) then
      local received_item = m.api.GetInboxItem( m.api.InboxFrame.openMailID )
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = money,
        cod = cod,
        returned = returned,
        gm = gm,
        icon = package_icon,
        item = received_item
      } )
    end
  else
    m.debug( "returning mail" )
  end

  m.orig.OpenMailFrame_OnHide()
end

function TurtleMail.send_mail_button_onclick()
  m.api.MailAutoCompleteBox:Hide()

  m.api.TurtleMail_To = m.api.SendMailNameEditBox:GetText()
  m.api.SendMailNameEditBox:HighlightText()

  m.sendmail_state = {
    to = m.api.TurtleMail_To,
    subject = MailSubjectEditBox:GetText(),
    body = m.api.SendMailBodyEditBox:GetText(),
    money = m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ),
    cod = m.api.SendMailCODButton:GetChecked(),
    attachments = m.sendmail_attachments(),
    numMessages = math.max( 1, m.sendmail_num_attachments() ),
  }

  m.sendmail_clear()
  m.sendmail_sending = true
  m.sendmail_send()
end

function TurtleMail.sendmail_load()
  m.api.SendMailFrame:EnableMouse( false )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarLeft", "BACKGROUND" )
  m.api.MailHorizontalBarLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarLeft:SetWidth( 256 )
  m.api.MailHorizontalBarLeft:SetHeight( 16 )
  m.api.MailHorizontalBarLeft:SetTexCoord( 0, 1, 0, .25 )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarRight", "BACKGROUND" )
  m.api.MailHorizontalBarRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarRight:SetWidth( 75 )
  m.api.MailHorizontalBarRight:SetHeight( 16 )
  m.api.MailHorizontalBarRight:SetTexCoord( 0, .29296875, .25, .5 )
  m.api.MailHorizontalBarRight:SetPoint( "LEFT", m.api.MailHorizontalBarLeft, "RIGHT" )

  m.api.SendMailMoneyText:SetJustifyH( "LEFT" )
  m.api.SendMailMoneyText:SetPoint( "TOPLEFT", 0, 0 )
  m.api.SendMailMoney:ClearAllPoints()
  m.api.SendMailMoney:SetPoint( "TOPLEFT", m.api.SendMailMoneyText, "BOTTOMLEFT", 5, -5 )
  m.api.SendMailMoneyGoldRight:SetPoint( "RIGHT", 20, 0 )
  do ({ m.api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyGold:SetMaxLetters( 7 )
  m.api.SendMailMoneyGold:SetWidth( 50 )
  m.api.SendMailMoneySilverRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneySilver:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneySilver:SetWidth( 28 )
  m.api.SendMailMoneySilver:SetPoint( "LEFT", m.api.SendMailMoneyGold, "RIGHT", 30, 0 )
  m.api.SendMailMoneyCopperRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneyCopper:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyCopper:SetWidth( 28 )
  m.api.SendMailMoneyCopper:SetPoint( "LEFT", m.api.SendMailMoneySilver, "RIGHT", 20, 0 )
  m.api.SendMailSendMoneyButton:SetPoint( "TOPLEFT", m.api.SendMailMoney, "TOPRIGHT", 20, 25 )

  -- hack to avoid automatic subject setting and button disabling from weird blizzard code
  MailMailButton = m.api.SendMailMailButton
  m.api.SendMailMailButton = setmetatable( {}, { __index = function() return function() end end } )
  m.api.SendMailMailButton_OnClick = m.send_mail_button_onclick
  MailSubjectEditBox = m.api.SendMailSubjectEditBox
  m.api.SendMailSubjectEditBox = setmetatable( {}, {
    __index = function( _, key )
      return function( _, ... )
        return MailSubjectEditBox[ key ]( MailSubjectEditBox, unpack( arg ) )
      end
    end,
  } )

  m.api.SendMailNameEditBox._SetText = m.api.SendMailNameEditBox.SetText
  function m.api.SendMailNameEditBox:SetText( ... )
  -- 确保在选择新收件人时能正常更新输入框内容
    local text = unpack(arg)
	 self:_SetText(text)
  end

  m.api.SendMailNameEditBox:SetScript( "OnShow", function()
    if m.api.TurtleMail_To then
      m.api.this:_SetText( m.api.TurtleMail_To )
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnChar", function()
    m.api.TurtleMail_To = nil
    GetSuggestions()
  end )
  m.api.SendMailNameEditBox:SetScript( "OnTabPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      if m.api.IsShiftKeyDown() then
        m.previous_match()
      else
        m.next_match()
      end
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEnterPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
      this:HighlightText( 0, 0 )
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEscapePressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
    else
      this:ClearFocus()
    end
  end )
  function m.api.SendMailNameEditBox.focusLoss()
    m.api.MailAutoCompleteBox:Hide()
  end

  m.api.SendMailCODAllButtonText:SetText( L[ "All mails" ] )
  m.api.SendMailCODAllButton:SetScript( "OnClick", m.set_cod_text )

  do

  end

  for _, editBox in { m.api.SendMailNameEditBox, m.api.SendMailSubjectEditBox } do
    editBox:SetScript( "OnEditFocusGained", function()
      this:HighlightText()
    end )
    editBox:SetScript( "OnEditFocusLost", function()
      (this.focusLoss or function() end)()
      this:HighlightText( 0, 0 )
    end )
    do
      local lastClick
      editBox:SetScript( "OnMouseDown", function()
        local x, y = m.api.GetCursorPosition()
        if lastClick and m.api.GetTime() - lastClick.t < .5 and x == lastClick.x and y == lastClick.y then
          this:SetScript( "OnUpdate", function()
            this:HighlightText()
            this:SetScript( "OnUpdate", nil )
          end )
        end
        lastClick = { t = m.api.GetTime(), x = x, y = y }
      end )
    end
  end
end

--@param bag number
--@param slot number
function TurtleMail.sendmail_attached( bag, slot )
  if not m.api.MailFrame:IsVisible() then return false end
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      return true
    end
  end
  if m.sendmail_state then
    for _, attachment in m.sendmail_state.attachments do
      if attachment[ 1 ] == bag and attachment[ 2 ] == slot then
        return true
      end
    end
  end
end

function TurtleMail.attachment_button_on_click()
  local attachedItem = this.item
  local cursorItem = m.get_cursor_item()
  if m.sendmail_set_attachment( cursorItem, this ) then
    if attachedItem then
      if arg1 == "LeftButton" then m.set_cursor_item( attachedItem ) end
      m.orig.PickupContainerItem( unpack( attachedItem ) )
      if arg1 ~= "LeftButton" then m.api.ClearCursor() end -- for the lock changed event
    end
  end
end

function TurtleMail.sendmail_remove_attachment( item )
  if not item then return end
  if type( item ) == "table" and m.sendmail_attached( item[ 1 ], item[ 2 ] ) then
    for i = 1, ATTACHMENTS_MAX do
      local btn = m.api[ "MailAttachment" .. i ]
      if btn.item and btn.item[ 1 ] == item[ 1 ] and btn.item[ 2 ] == item[ 2 ] then
        m.api[ "MailAttachment" .. i ].item = nil
        m.orig.PickupContainerItem( unpack( item ) )
        m.api.ClearCursor()
        m.api.SendMailFrame_Update()
        return
      end
    end
  end
end

-- requires an item lock changed event for a proper update
---@param item table
---@param slot number?
function TurtleMail.sendmail_set_attachment( item, slot )
  if item and not m.sendmail_pickup_mailable( item ) then
    m.api.ClearCursor()
    return
  elseif not slot then
    for i = 1, ATTACHMENTS_MAX do
      if not m.api[ "MailAttachment" .. i ].item then
        slot = m.api[ "MailAttachment" .. i ]
        break
      end
    end
  end
  if slot then
    if not (item or slot.item) then return true end
    slot.item = item
    m.api.ClearCursor()
    m.api.SendMailFrame_Update()
    return true
  end
end

---@param item table
function TurtleMail.sendmail_pickup_mailable( item )
  m.api.ClearCursor()
  m.orig.ClickSendMailItemButton()
  m.api.ClearCursor()
  m.orig.PickupContainerItem( unpack( item ) )
  m.orig.ClickSendMailItemButton()
  local mailable = m.api.GetSendMailItem() and true or false
  m.orig.ClickSendMailItemButton()
  return mailable
end

function TurtleMail.sendmail_num_attachments()
  local x = 0
  for i = 1, ATTACHMENTS_MAX do
    if m.api[ "MailAttachment" .. i ].item then
      x = x + 1
    end
  end
  return x
end

function TurtleMail.sendmail_attachments()
  local t = {}
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item then
      table.insert( t, btn.item )
    end
  end
  return t
end

function TurtleMail.sendmail_clear()
  local anyItem
  for i = 1, ATTACHMENTS_MAX do
    anyItem = anyItem or m.api[ "MailAttachment" .. i ].item
    m.api[ "MailAttachment" .. i ].item = nil
  end
  if anyItem then
    m.api.ClearCursor()
    m.api.PickupContainerItem( unpack( anyItem ) )
    m.api.ClearCursor()
  end
  MailMailButton:Disable()
  m.api.SendMailNameEditBox:SetText ""
  m.api.SendMailNameEditBox:SetFocus()
  MailSubjectEditBox:SetText ""
  m.api.SendMailBodyEditBox:SetText ""
  m.api.MoneyInputFrame_ResetMoney( m.api.SendMailMoney )
  m.api.SendMailRadioButton_OnClick( 1 )

  m.api.SendMailFrame_Update()
end

function TurtleMail.sendmail_send()
  local item = table.remove( m.sendmail_state.attachments, 1 )
  if item then
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
    m.orig.PickupContainerItem( unpack( item ) )
    m.orig.ClickSendMailItemButton()

    if not m.api.GetSendMailItem() then
      m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473TurtleMail|r: " .. m.api.ERROR_CAPS, 1, 0, 0 )
      return
    end
  end

  local amount = m.sendmail_state.money
  m.sendmail_state.sent_money = m.sendmail_state.money
  m.sendmail_state.sent = false

  if amount > 0 then
    if not m.api.SendMailCODAllButton:GetChecked() then
      m.sendmail_state.money = 0
    end
    if m.sendmail_state.cod then
      m.sendmail_state.cod = amount
      m.api.SetSendMailCOD( amount )
    else
      m.sendmail_state.money = 0
      m.api.SetSendMailMoney( amount )
    end
  end

  local subject = m.sendmail_state.subject
  if subject == "" then
    if item then
      local item_name, texture, stack_count = m.api.GetSendMailItem()
      subject = item_name .. (stack_count > 1 and " (" .. stack_count .. ")" or "")
      m.sendmail_state.item = item_name
      m.sendmail_state.icon = texture
    else
      subject = "<" .. m.api.NO_ATTACHMENTS .. ">"
    end
  elseif m.sendmail_state.numMessages > 1 then
    subject = subject .. string.format( " [%d/%d]", m.sendmail_state.numMessages - getn( m.sendmail_state.attachments ),
      m.sendmail_state.numMessages )
  end

  m.sendmail_state.sent_subject = subject

  m.debug( "SendMail" )
  m.api.SendMail( m.sendmail_state.to, subject, m.sendmail_state.body )

  if getn( m.sendmail_state.attachments ) == 0 then
    m.sendmail_sending = false
  end
end

do
  local inputLength
  local matches = {}
  local index

  local function complete()
    m.api.SendMailNameEditBox:SetText( matches[ index ] )
    m.api.SendMailNameEditBox:HighlightText( inputLength, -1 )
    for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
      local button = m.api[ "MailAutoCompleteButton" .. i ]
      if i == index then
        button:LockHighlight()
      else
        button:UnlockHighlight()
      end
    end
  end

  function TurtleMail.previous_match()
    if index then
      index = index > 1 and index - 1 or getn( matches )
      complete()
    end
  end

  function TurtleMail.next_match()
    if index then
      ---@diagnostic disable-next-line: undefined-global
      index = mod( index, getn( matches ) ) + 1
      complete()
    end
  end

  function TurtleMail.select_match( i )
    index = i
    complete()
    m.api.MailAutoCompleteBox:Hide()
    m.api.SendMailNameEditBox:HighlightText( 0, 0 )
  end

  function GetSuggestions()
    local input = m.api.SendMailNameEditBox:GetText()
    inputLength = string.len( input )

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, 0 )
    index = nil

	local autoCompleteNames = {}
	local key = get_realm_faction_key()
	local names_table = m.api.TurtleMail_AutoCompleteNames[ key ] or {}
	for name, time in pairs( names_table ) do
	  table.insert( autoCompleteNames, { name = name, time = time } )
	end

    table.sort( autoCompleteNames, function( a, b ) return b.time < a.time end )

    local ignore = { [ m.api.UnitName "player" ] = true }
    local function process( name )
      if name then
        if not ignore[ name ] and string.find( string.upper( name ), string.upper( input ), nil, true ) == 1 then
          table.insert( matches, name )
        end
        ignore[ name ] = true
      end
    end
    for _, t in autoCompleteNames do
      process( t.name )
    end
    for i = 1, m.api.GetNumFriends() do
      process( m.api.GetFriendInfo( i ) )
    end
    for i = 1, m.api.GetNumGuildMembers( true ) do
      process( m.api.GetGuildRosterInfo( i ) )
    end

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, math.min( getn( matches ), m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS ) )
    if getn( matches ) > 0 and (getn( matches ) > 1 or input ~= matches[ 1 ]) then
      for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
        local button = m.api[ "MailAutoCompleteButton" .. i ]
        if i <= getn( matches ) then
          button:SetText( matches[ i ] )
          button:GetFontString():SetPoint( "LEFT", button, "LEFT", 15, 0 )
          button:Show()
        else
          button:Hide()
        end
      end
      m.api.MailAutoCompleteBox:SetHeight( getn( matches ) * m.api.MailAutoCompleteButton1:GetHeight() + 35 )
      m.api.MailAutoCompleteBox:SetWidth( 120 )
      m.api.MailAutoCompleteBox:Show()
      index = 1
      complete()
    else
      m.api.MailAutoCompleteBox:Hide()
    end
  end
end

function TurtleMail.log.load()
  m.api.TurtleMailLogTitleText:SetText( L[ "Log" ] )
  m.api.MailFrameTab3:SetText( L[ "Log" ] )

  local font_file = m.pfui_skin_enabled and m.api.pfUI.font_default or "FONTS\\ARIALN.TTF"
  local font_size = 11

  for i = 1, 10 do
    m.api[ "TurtleMailLogItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetJustifyH( "RIGHT" )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if i > 1 then
      m.api[ "TurtleMailLogItem" .. i ]:SetPoint( "TOPLEFT", m.api[ "TurtleMailLogItem" .. i - 1 ], "BOTTOMLEFT", 0, -1 )
    end
  end
  m.api.TurtleMailLogItem10Background:Hide()

  m.api.TurtleMailLogStatusText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogStatusText:SetFont( "Fonts\\FRIZQT__.TTF", 10 )
  m.api.TurtleMailLogScrollFrameScrollBar:SetValueStep( 1 )
  m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnValueChanged", m.log.on_scroll_value_changed )

  m.api.TurtleMailLogScrollFrame:SetScript( "OnMouseWheel", function()
    m.log.scroll( arg1 * 10 )
  end )
  m.api.TurtleMailLogScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( 10 )
  end )
  m.api.TurtleMailLogScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( -10 )
  end )

  m.api.TurtleMailLogFiltersButton:SetText( L[ "Filters" ] )
  m.api.TurtleMailLogFiltersButton:GetFontString():SetPoint( "LEFT", m.api.TurtleMailLogFiltersButton, "LEFT", 10, 0 )

  m.api.TurtleMailLogFiltersButton:SetScript( "OnMouseDown", function()
    m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -3 )
  end )
  m.api.TurtleMailLogFiltersButton:SetScript( "OnMouseUp", function()
    m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -1 )
  end )

  m.api.TurtleMailLogStartTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogStartTimeButton:SetScale( 0.9 )
  m.api.TurtleMailLogEndTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogEndTimeButton:SetScale( 0.9 )

  m.api.TurtleMailLogStartTime:SetScript( "OnClick", function()
    m.api.TurtleMailLogStartTimeText:SetText( "" )
    m[ m.current_log_type .. "_start_time" ] = nil
    m.log.populate( m.current_log_type )
  end )
  m.api.TurtleMailLogEndTime:SetScript( "OnClick", function()
    m.api.TurtleMailLogEndTimeText:SetText( "" )
    m[ m.current_log_type .. "_end_time" ] = nil
    m.log.populate( m.current_log_type )
  end )

  m.api.TurtleMailLogPlayersDropDown:SetScale( 0.9 )
  m.api.UIDropDownMenu_SetText( L[ "All players"] , m.api.TurtleMailLogPlayersDropDown )

  m.dropdown_filters = m.api.CreateFrame( "Frame", "TurtleMailDropDownFilters" )
  m.dropdown_filters.displayMode = "MENU"
  m.dropdown_filters.info = {}
end

function TurtleMail.log.players_dropdown_on_load()
  m.api.UIDropDownMenu_Initialize( m.api.TurtleMailLogPlayersDropDown, function()
    local info = {}
    info.notCheckable = 1
    info.text = L[ "All players"]
    info.arg1 = info.text
    info.arg2 = "All"
    info.func = m.log.select_player
    m.api.UIDropDownMenu_AddButton( info )

    if not m.current_log_type then return end

    local players = {}
    for _, v in ipairs( m.api.TurtleMail_Log[ m.current_log_type ] ) do
      if v then
        players[ v.participant ] = players[ v.participant ] and players[ v.participant ] + 1 or 1
      end
    end

    for player, count in pairs( players ) do
      info.text = player .. " (" .. count .. ")"
      info.arg1 = player
      info.arg2 = nil
      m.api.UIDropDownMenu_AddButton( info )
    end
  end )
end

function TurtleMail.log.select_player( player, is_all )
  m.api.UIDropDownMenu_SetText( player, m.api.TurtleMailLogPlayersDropDown )
  if is_all then
    m.filter_player = nil
  else
    m.filter_player = player
  end
  m.log.populate( m.current_log_type )
end

function TurtleMail.log.filter_dropdown()
  if m.dropdown_filters.initialize ~= TurtleMail.log.filters_menu then
    m.api.CloseDropDownMenus()
    m.dropdown_filters.initialize = TurtleMail.log.filters_menu
  end
  m.api.ToggleDropDownMenu( 1, nil, m.dropdown_filters, this:GetName(), 0, 0 )
end

function TurtleMail.log.filters_menu( level )
  local filters = m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ] or {}
  local info = {}
  info.keepShownOnClick = 1

  local values = { "Money", "付款取信", "其他" }
  if m.current_log_type == "Received" then
    table.insert( values, "Returned" )
    table.insert( values, "AH" )
  end

  if level == 1 then
    for _, filter in values do
      info.text = L[ filter ]
      info.checked = filters[ filter ]
      info.arg1 = filter
      info.func = m.log.toggle_filter
      if filter == "AH" then info.hasArrow = 1 end

      m.api.UIDropDownMenu_AddButton( info, level )
    end
  elseif level == 2 then
    for _, filter in { "拍卖成功", "已取消", "已到期", "竞拍", "一口价" } do
      info.text = L[ filter ]
      info.checked = filters[ "AH" .. filter ]
      info.arg1 = filter
      info.arg2 = "AH"
      info.func = m.log.toggle_filter
      m.api.UIDropDownMenu_AddButton( info, level )
    end
  end
end

function TurtleMail.log.toggle_filter( filter, parent_filter )
  if not parent_filter then parent_filter = "" end
  local filter_value = m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ]

  m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ] = not filter_value
  m.log.populate( m.current_log_type )
end

function TurtleMail.log.show_calendar()
  if m.calendar.is_visible() then
    m.calendar.hide()
  else
    local text = string.gsub( this:GetName(), "Button", "Text" )
    m.calendar.show( m.api.TurtleMail_Log[ m.current_log_type ], time(), this, function( selected_date )
      local date_str = date( L[ "date_format" ], selected_date )
      m.api[ text ]:SetText( date_str )

      local v = m.current_log_type .. (string.find( text, "Start" ) and "_start_time" or "_end_time")
      m[ v ] = selected_date
      m.log.populate( m.current_log_type )
    end )
  end
end

function TurtleMail.log.scroll( step )
  local scroll_bar = m.api.TurtleMailLogScrollFrameScrollBar
  local current = scroll_bar:GetValue()
  local min, max = scroll_bar:GetMinMaxValues()
  local new = current - step

  if new >= max then
    scroll_bar:SetValue( max )
  elseif new <= min then
    scroll_bar:SetValue( 0 )
  else
    scroll_bar:SetValue( new )
  end
end

function TurtleMail.log.on_scroll_value_changed()
  local function round( num )
    return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51)
  end

  local scrollBar = m.api.TurtleMailLogScrollFrameScrollBar
  local scrollUp = m.api.TurtleMailLogScrollFrameScrollBarScrollUpButton
  local scrollDown = m.api.TurtleMailLogScrollFrameScrollBarScrollDownButton

  local minVal, maxVal = scrollBar:GetMinMaxValues()
  local currentVal = round( scrollBar:GetValue() )

  if currentVal <= round( minVal ) then
    scrollUp:Disable()
  else
    scrollUp:Enable()
  end

  if currentVal >= round( maxVal ) then
    scrollDown:Disable()
  else
    scrollDown:Enable()
  end

  m.log.populate( m.current_log_type, currentVal )
end

---@alias LogType
---| "Sent"
---| "Received"

---@param log_type LogType
---@param state table
function TurtleMail.log.add( log_type, state )
  if not m.log_enabled then return end
  m.debug( "Logging " .. log_type .. " message" )

  local data = {
    timestamp = time(),
    icon = state.icon,
    item = state.item
  }

  if state.cod and state.cod > 0 then data.cod = tonumber( state.cod ) end
  if log_type == "Sent" then
    data.participant = state.to
    data.subject = state.sent_subject
    if state.send_money and state.sent_money > 0 then data.money = tonumber( state.sent_money ) end
  else -- Received
    data.participant = state.from
    data.subject = state.subject
    data.returned = state.returned
    data.gm = state.gm

    if state.money and state.money > 0 then data.money = tonumber( state.money ) end

    if string.find( data.subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Sold"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Removed"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Expired"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Won"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Outbid"
    end
  end

  table.insert( m.api.TurtleMail_Log[ log_type ], data )
end

---@param log_type LogType
---@param index number?
function TurtleMail.log.populate( log_type, index )
  m.current_log_type = log_type
  local filters = m.api.TurtleMail_Log[ "Settings" ][ log_type .. "Filters" ] or {}
  local start_time = m[ log_type .. "_start_time" ]
  local end_time = m[ log_type .. "_end_time" ]
  if start_time then start_time = start_time - 43200 end
  if end_time then end_time = end_time + 43140 end

  local log = m.filter( m.api.TurtleMail_Log[ log_type ], function( item )
    local ret =
        (filters.Money and item.money and item.money > 0 and (not item.cod or item.cod == 0) and not item.ah)
        or
        (filters.COD and item.cod and item.cod > 0)
        or
        (filters.Other and (not item.cod or item.cod == 0) and not item.ah and not item.returned and (not item.money or item.money == 0))
        or
        (filters.Returned and item.returned)
        or
        (filters.AH and filters.AHWon and item.ah == "Won")
        or
        (filters.AH and filters.AHSold and item.ah == "Sold")
        or
        (filters.AH and filters.AHCancelled and item.ah == "Removed")
        or
        (filters.AH and filters.AHOutbid and item.ah == "Outbid")
        or
        (filters.AH and filters.AHExpired and item.ah == "Expired")

    if m.filter_player then
      ret = ret and item.participant == m.filter_player
    end
    if start_time then
      ret = ret and item.timestamp >= start_time
    end
    if end_time then
      ret = ret and item.timestamp <= end_time
    end

    return ret
  end )

  m.api.TurtleMailLogStartTimeText:SetText( start_time and date( L[ "date_format" ], start_time ) or "" )
  m.api.TurtleMailLogEndTimeText:SetText( end_time and date( L[ "date_format" ], end_time ) or "" )

  if not log then return end
  local log_count = getn( log )

  m.api.TurtleMailLogScrollFrameScrollBar:SetMinMaxValues( 0, math.max( 0, log_count - 10 ) )

  if not index then
    m.api.TurtleMailLogScrollFrameScrollBar:SetValue( log_count - 10 )
    m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnUpdate", function()
      m.api.TurtleMailLogScrollFrameScrollBar:SetValue( log_count - 10 )
      m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnUpdate", nil )
    end )

    index = math.max( 0, log_count - 10 )
  end

  m.api.TurtleMailLogTitleText:SetText( string.format( "%s %s", L[ "log_type" ], L[ "Log" ] ) )
  m.api.TurtleMailLogStatusText:SetText( string.format( "显示%d-%d，总共%d", (index == 0 and log_count == 0) and index or index + 1,
  math.min( log_count, index + 10 ), log_count ) )

  for i = 1, 10 do
    if log[ index + i ] then
      local entry = log[ index + i ]

      m.api[ "TurtleMailLogItem" .. i .. "IconTexture" ]:SetTexture( entry.icon or "Interface/Icons/INV_Misc_Note_01" )
      m.api[ "TurtleMailLogItem" .. i .. "Icon" ].item = entry.item
      m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetText( date( L[ "date_format" ] .. " " .. L[ "time_format" ], entry.timestamp ) )
      m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetText( entry.subject )

      m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "" )
      if entry.ah then
        m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetText( "" )
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "Interface\\Addons\\TurtleMail\\TurtleMail-AH.blp" )
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", 4, -10 )
      else
        m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetText( entry.participant )
      end
      if entry.returned then
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "Interface\\Addons\\TurtleMail\\TurtleMail-RetArrow.blp" )
        local w = m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:GetStringWidth()
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", -w + 4, -9 )
      end

      if entry.money and entry.money > 0 then
        local cod = (entry.cod and entry.cod > 0) and "COD: " or " "
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( cod .. m.format_money( entry.money ) )
      elseif entry.cod then
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( "COD" .. (entry.cod > 1 and (": " .. m.format_money( entry.cod )) or "") )
      else
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( "" )
      end

      m.api[ "TurtleMailLogItem" .. i ]:Show();
    else
      m.api[ "TurtleMailLogItem" .. i ]:Hide();
    end
  end
end

function TurtleMail.pfui_skin()
  if m.api.IsAddOnLoaded( "pfUI" ) and m.api.pfUI and m.api.pfUI.api and m.api.pfUI.env and m.api.pfUI.env.C then
    m.api.pfUI:RegisterSkin( "TurtleMail", "vanilla", function()
      -- Don't apply our skin when Mailbox skin is disabled because it doesn't make sense.
      if m.api.pfUI.env.C.disabled and (m.api.pfUI.env.C.disabled[ "skin_TurtleMail" ] == "1" or m.api.pfUI.env.C.disabled[ "skin_Mailbox" ] == "1") then
        return
      end
      m.pfui_skin_enabled = true
      local rawborder, border = m.api.pfUI.api.GetBorderSize()
      local bpad = rawborder > 1 and border - m.api.pfUI.api.GetPerfectPixel() or m.api.pfUI.api.GetPerfectPixel()

      --Inbox
      m.api.pfUI.api.SkinButton( m.api.TurtleMailOpenMailButton )

      --Sendmail
      m.api.MailHorizontalBarLeft:SetTexture( "" )
      m.api.MailHorizontalBarRight:SetTexture( "" )

      for i = 1, 21 do
        local button = m.api[ "MailAttachment" .. i ]
        m.api.pfUI.api.StripTextures( button )
        m.api.pfUI.api.SkinButton( button, nil, nil, nil, nil, true )
        local orig = button.SetNormalTexture
        button.SetNormalTexture = function( self, tex )
          orig( self, tex )

          if button.item then
            m.api.pfUI.api.HandleIcon( self, self:GetNormalTexture() )

            local link = m.api.GetContainerItemLink( button.item[ 1 ], button.item[ 2 ] )
            if link then
              local _, _, linkstr = string.find( link, "(item:%d+:%d+:%d+:%d+)" )
              local _, _, quality = m.api.GetItemInfo( linkstr )
              local r, g, b = m.api.GetItemQualityColor( quality )
              self:SetBackdropBorderColor( r, g, b, 1 )
            end
          else
            self:SetBackdropBorderColor( m.api.pfUI.api.GetStringColor( m.api.pfUI_config.appearance.border.color ) )
          end
        end
      end

      --Log
      m.api.pfUI.api.SkinTab( m.api.MailFrameTab3 )
      m.api.MailFrameTab3:ClearAllPoints()
      m.api.MailFrameTab3:SetPoint( "LEFT", m.api.MailFrameTab2, "RIGHT", border * 2 + 1, 0 )

      m.api.TurtleMailLogTitleText:ClearAllPoints()
      m.api.TurtleMailLogTitleText:SetPoint( "TOP", m.api.MailFrame.backdrop, "TOP", 0, -10 )

      m.api.pfUI.api.CreateBackdrop( m.api.TurtleMailLogScrollFrame )

      m.api.TurtleMailLogScrollFrame:SetHeight( 307 )
      m.api.TurtleMailLogScrollFrame:ClearAllPoints()
      m.api.TurtleMailLogScrollFrame:SetPoint( "TOPLEFT", 23, -90 )
      m.api.TurtleMailLogScrollFrame:SetWidth( 299 )
      m.api.TurtleMailLogEntriesFrame:ClearAllPoints()
      m.api.TurtleMailLogEntriesFrame:SetPoint( "TOPLEFT", 23, -90 )
      m.api.TurtleMailLogEntriesFrame:SetWidth( 299 )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogItem10 )
      m.api.pfUI.api.SkinScrollbar( m.api.TurtleMailLogScrollFrameScrollBar )
      m.api.TurtleMailLogScrollFrameScrollBar:SetPoint( "TOPLEFT", m.api.TurtleMailLogScrollFrame, "TOPRIGHT", 6, -14 )
      m.api.TurtleMailLogScrollFrameScrollBar:SetPoint( "BOTTOMLEFT", m.api.TurtleMailLogScrollFrame, "BOTTOMRIGHT", 6, 14 )

      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogSentButton )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogReceivedButton )
      m.api.TurtleMailLogReceivedButton:ClearAllPoints()
      m.api.TurtleMailLogReceivedButton:SetPoint( "RIGHT", m.api.TurtleMailLogSentButton, "LEFT", -2 * bpad, 0 )

      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogFiltersButton )
      m.api.TurtleMailLogFiltersButton:SetPoint( "TOPLEFT", 21, -58 )
      m.api.TurtleMailLogFiltersButton:GetFontString():SetFont( m.api.pfUI.font_default, 12 )
      m.api.TurtleMailLogFiltersButton:GetFontString():SetPoint( "TOPLEFT", 4, -4.5 )
      m.api.TurtleMailLogFiltersButton:SetWidth( 50 )
      m.api.TurtleMailLogFiltersButton:SetHeight( 20 )
      m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", -4, -1 )
      m.api.TurtleMailLogFiltersButtonArrow:SetWidth( 8.5 )
      m.api.TurtleMailLogFiltersButtonArrow:SetHeight( 8.5 )
      m.api.TurtleMailLogFiltersButtonArrow:SetTexture( m.api.pfUI.media[ "img:down" ] )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogStartTime )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogStartTime )
      m.api.pfUI.api.SkinArrowButton( m.api.TurtleMailLogStartTimeButton, "down", 16 )
      m.api.TurtleMailLogStartTime:SetPoint( "TOPLEFT", 77, -58 )
      m.api.TurtleMailLogStartTimeText:SetPoint( "LEFT", 5, 0 )
      m.api.TurtleMailLogStartTimeButton:SetPoint( "LEFT", m.api.TurtleMailLogStartTime, "RIGHT", -19, 0 )
      m.api.TurtleMailLogStartTimeTitle:SetPoint( "TOPLEFT", 1, 13 )
      m.api.TurtleMailLogStartTimeTitle:SetFont( m.api.pfUI.font_default, 10 )
      m.api.TurtleMailLogStartTimeTitle:SetText( L[ "Period start" ] )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogEndTime )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogEndTime )
      m.api.pfUI.api.SkinArrowButton( m.api.TurtleMailLogEndTimeButton, "down", 16 )
      m.api.TurtleMailLogEndTime:SetPoint( "TOPLEFT", 163, -58 )
      m.api.TurtleMailLogEndTimeText:SetPoint( "LEFT", 5, 0 )
      m.api.TurtleMailLogEndTimeButton:SetPoint( "LEFT", m.api.TurtleMailLogEndTime, "RIGHT", -19, 0 )
      m.api.TurtleMailLogEndTimeTitle:SetPoint( "TOPLEFT", 1, 13 )
      m.api.TurtleMailLogEndTimeTitle:SetFont( m.api.pfUI.font_default, 10 )
      m.api.TurtleMailLogEndTimeTitle:SetText( L[ "Period end" ] )

      m.api.pfUI.api.SkinDropDown( m.api.TurtleMailLogPlayersDropDown, nil, nil, nil, true )
      m.api.UIDropDownMenu_SetWidth( 90, m.api.TurtleMailLogPlayersDropDown )
      m.api.TurtleMailLogPlayersDropDown:SetScale( 1 )
      m.api.TurtleMailLogPlayersDropDown:SetPoint( "TOPLEFT", 224, -54 )
      m.api.TurtleMailLogPlayersDropDown.backdrop:SetPoint( "TOPLEFT", 26, -4 )
      m.api.TurtleMailLogPlayersDropDown.backdrop:SetPoint( "BOTTOMRIGHT", -20, 8 )
      m.api.TurtleMailLogPlayersDropDown.button.backdrop:SetWidth( 16 )
      m.api.TurtleMailLogPlayersDropDown.button.backdrop:SetHeight( 16 )

      local label = m.api.TurtleMailLogFrame:CreateFontString( nil, "BACKGROUND", "GameFontNormal" )
      label:SetFont( m.api.pfUI.font_default, 10 )
      label:SetPoint( "TOPLEFT", 251, -45 )
      label:SetText( L[ "Players" ] )
      -- 美化 COD 复选框（带 pfUISkinned 防重复）
      if m.api.TurtleMailCODCheckButton and not m.api.TurtleMailCODCheckButton.pfUISkinned then
        m.api.TurtleMailCODCheckButton.pfUISkinned = true
        m.api.pfUI.api.SkinCheckbox(m.api.TurtleMailCODCheckButton)
      end

      -- 美化 MailTo 下拉按钮（标准 UIDropDownMenu，用 pfUI 自带 SkinDropDown，箭头由它自动补）
      local mailToBtn = m.api.MailToDropDownMenu
      if mailToBtn and not mailToBtn.pfUISkinned then
        mailToBtn.pfUISkinned = true
        m.api.pfUI.api.SkinDropDown(mailToBtn, nil, nil, nil, true)
        -- 隐藏外层 backdrop，避免与旁边控件重叠（保留按钮的金色箭头）
        if mailToBtn.backdrop then
          mailToBtn.backdrop:Hide()
        end
      end

      -- 美化收件人自动补全建议框（输入名字后弹出的玩家列表，Tab 切换）
      if m.api.MailAutoCompleteBox then
        -- 去掉原生 tooltip 背景/边框，换成 pfUI 背景
        -- 这里用 legacy 模式（第三个参数 true），让 pfUI 直接替换原生 SetBackdrop，
        -- 避免非 legacy 模式下原生 tooltip 背景纹理残留导致的指令行黄底问题
        m.api.pfUI.api.CreateBackdrop(m.api.MailAutoCompleteBox, nil, true, .75)
        for i = 1, (m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS or 5) do
          local btn = m.api["MailAutoCompleteButton" .. i]
          if btn then
            m.api.pfUI.api.SkinButton(btn)
          end
        end
        if m.api.MailAutoCompleteInstructions then
          m.api.MailAutoCompleteInstructions:SetFont(m.api.pfUI.font_default, 10)
          -- 指令行"按 Tab 键"补一层与按钮一致的背景条：
          -- 按钮区是 box 背景 + 按钮背景两层叠加，指令行只有 box 一层，会比按钮区浅，需补齐
          if not m.api.MailAutoCompleteInstructions.bg then
            local bg = m.api.CreateFrame("Frame", nil, m.api.MailAutoCompleteBox)
            bg:SetPoint("BOTTOMLEFT", m.api.MailAutoCompleteBox, "BOTTOMLEFT", 1, 1)
            bg:SetPoint("BOTTOMRIGHT", m.api.MailAutoCompleteBox, "BOTTOMRIGHT", -1, 1)
            bg:SetHeight(20)
            m.api.pfUI.api.CreateBackdrop(bg, nil, true)
            m.api.MailAutoCompleteInstructions:SetParent(bg)
            m.api.MailAutoCompleteInstructions:ClearAllPoints()
            m.api.MailAutoCompleteInstructions:SetPoint("LEFT", bg, "LEFT", 14, 0)
            m.api.MailAutoCompleteInstructions.bg = bg
          end
        end
      end
    end )
  end
end

function TurtleMail.filter( t, f, extract_field )
  if not t then return nil end
  if type( f ) ~= "function" then return t end

  local result = {}

  for i = 1, getn( t ) do
    local v = t[ i ]
    local value = type( v ) == "table" and extract_field and v[ extract_field ] or v
    if f( value ) then table.insert( result, v ) end
  end

  return result
end

function TurtleMail.info( message )
  m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s", message ) )
end

function TurtleMail.dump( o )
  if not o then return "nil" end
  if type( o ) ~= 'table' then return tostring( o ) end

  local entries = 0
  local s = "{"

  for k, v in pairs( o ) do
    if (entries == 0) then s = s .. " " end
    local key = type( k ) ~= "number" and '"' .. k .. '"' or k
    if (entries > 0) then s = s .. ", " end
    s = s .. "[" .. key .. "] = " .. m.dump( v )
    entries = entries + 1
  end

  if (entries > 0) then s = s .. " " end
  return s .. "}"
end

function TurtleMail.debug( ... )
  if m.debug_enabled then
    local messages = ""
    for i = 1, getn( arg ) do
      local message = arg[ i ]
      if message then
        messages = messages == "" and "" or messages .. ", "
        if type( message ) == 'table' then
          messages = messages .. TurtleMail.dump( message )
        else
          messages = messages .. message
        end
      end
    end

    m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s", messages ) )
  end
end

TurtleMail:init()