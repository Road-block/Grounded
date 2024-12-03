local grounded = GroundedFrame

GroundedSavedBinds = {} -- per-character savedvar of bindings

-- for iterating over inset frames
local insets = {"listInset","bindInset"}

-- indexes into a bind
local NAME_INDEX = 1 -- name of spell or item
local BIND_INDEX = 2 -- key bound to spell or item
local ICON_INDEX = 3 -- icon of spell or item
local DOWN_INDEX = 4 -- macrotext to run on down
local UP_INDEX = 5 -- macrotext to run on up
-- flag for the user being on a classic client
local CLASSIC_CLIENT = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
local CLIENT_BUILD = select(4,GetBuildInfo())
-- format for default down/up macros
local DOWN_TEMPLATE = "/cast %s"
local UP_TEMPLATE = "/stopspelltarget\n/cast [@cursor] %s"

-- slash command to toggle window (alternative to button in spellbook)
SLASH_GROUNDED1 = "/grounded"
SlashCmdList["GROUNDED"] = function(msg)
    grounded:SetShown(not grounded:IsVisible())
end

local function getSpecIndex(...)
    if _G.GetActiveTalentGroup then
        return GetActiveTalentGroup(...)
    elseif _G.GetActiveSpecGroup then
        return GetActiveSpecGroup(...)
    else
        return 1 -- client with no dual spec, use a default
    end
end

-- wrapper for GetSpellInfo
local function getSpellInfo(spellID)
    if CLIENT_BUILD < 110000 then
        return GetSpellInfo(spellID)
    else
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, info.rank, info.icon, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIcon
        end
    end
end

local function getSpellSubtext(spellID)
    if CLIENT_BUILD < 110000 then
        return GetSpellSubtext(spellID)
    else
        return C_Spell.GetSpellSubtext(spellID)
    end
end

local function getSpellTexture(spellID)
    if CLIENT_BUILD < 110000 then
        return GetSpellTexture(spellID)
    else
        return C_Spell.GetSpellTexture(spellID)
    end
end

local function charToSpec(specIndex)
    local specContainer = {}
    for i=#GroundedSavedBinds,1,-1 do
        local spec = GroundedSavedBinds[i]
        if spec[1] and (type(spec[1]) ~= "table") then -- not a bind array, old sv
            -- migrate into the spec container
            tinsert(specContainer,tremove(GroundedSavedBinds,i))
        end
    end
    GroundedSavedBinds[specIndex] = GroundedSavedBinds[specIndex] or specContainer
    grounded.savedBinds = GroundedSavedBinds[specIndex]
end

function grounded:OnEvent(event,...)
    if self[event] then
        self[event](self,...)
    end
end

-- on login finish setting up UI
function grounded:PLAYER_LOGIN()
    grounded._specIndex = getSpecIndex()
    charToSpec(grounded._specIndex)
    if C_EventUtils.IsEventValid("ACTIVE_TALENT_GROUP_CHANGED") then
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    end
    -- finish setting up UI
    if CLASSIC_CLIENT then
        self.portrait:SetTexture("Interface\\AddOns\\Grounded\\textures")
        self.portrait:SetTexCoord(0,0.5,0,0.5)
        self.TitleText:SetText("Grounded") -- move title down a bit
        self.TitleText:ClearAllPoints()
        self.TitleText:SetPoint("TOPLEFT",32,-6)
        self.TitleText:SetPoint("TOPRIGHT",0,-6)
    else
        self.PortraitContainer.portrait:SetTexture("Interface\\AddOns\\Grounded\\textures")
        self.PortraitContainer.portrait:SetTexCoord(0,0.5,0,0.5)
        self.TitleContainer.TitleText:SetText("Grounded")
    end
    -- setting font of down/up editboxes to ChatFontNormal and script handlers
    self.bindInset.scrollFrame.content.macroFrame.downEditBox.EditBox:SetFontObject("ChatFontNormal")
    self.bindInset.scrollFrame.content.macroFrame.upEditBox.EditBox:SetFontObject("ChatFontNormal")
    -- when text changes in macro editboxes verify save button (can't have an empty macrotext if used)
    self.bindInset.scrollFrame.content.macroFrame.downEditBox.EditBox:SetScript("OnTextChanged",function() self.bindInset:UpdatePanelButtons() end)
    self.bindInset.scrollFrame.content.macroFrame.upEditBox.EditBox:SetScript("OnTextChanged",function() self.bindInset:UpdatePanelButtons() end)
    -- disable mousewheel on macro editboxes within the scrollframe (otherwise it's annoying to mousewheel scroll parent)
    self.bindInset.scrollFrame.content.macroFrame.downEditBox:SetScript("OnMouseWheel",nil)
    self.bindInset.scrollFrame.content.macroFrame.upEditBox:SetScript("OnMouseWheel",nil)

    -- set up toggle button in spellbook
    if CLIENT_BUILD<110000 then
        GroundedToggleButton:SetParent(SpellBookFrame)

        if CLASSIC_CLIENT then -- on classic clients, move button in further
            GroundedToggleButton:SetPoint("TOPRIGHT",-44,-42)
        else
            GroundedToggleButton:SetPoint("TOPRIGHT",-24,-36)
        end

        -- only show button when bookType is spell
        hooksecurefunc("SpellBookFrame_Update",function(self)
            GroundedToggleButton:SetShown(SpellBookFrame.bookType=="spell")
        end)
    else -- for TWW, wait until Blizzard_PlayerSpells is loaded to attach toggle button to spellbook
        self:RegisterEvent("ADDON_LOADED")
    end
    -- finally, set up secure buttons to cast stuff
    self:UpdateSecureButtons()
end

function grounded:ACTIVE_TALENT_GROUP_CHANGED(...)
    local currSpec, prevSpec = ...
    grounded._specIndex = currSpec
    charToSpec(grounded._specIndex)
    grounded:UpdateSecureButtons()
end

-- entering combat (this is only active when window on screen)
function grounded:PLAYER_REGEN_DISABLED()
    self.combatWarning:Show()
end

-- leaving combat (this is only active when window on screen)
function grounded:PLAYER_REGEN_ENABLED()
    self.combatWarning:Hide()
end

-- in TWW, Blizzard_PlayerSpells loads when the spellbook is loaded
function grounded:ADDON_LOADED(addon)
    if addon=="Blizzard_PlayerSpells" then
        self:UnregisterEvent("ADDON_LOADED")
        GroundedToggleButton:SetParent(PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame)
        GroundedToggleButton:SetPoint("TOPRIGHT",-26,-12)
    end
end

-- when window shown, always start at listInset
function grounded:OnShow()
    self:ShowInset("listInset")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.combatWarning:SetShown(InCombatLockdown())
end

-- don't need to listen for combat events when window isn't up
function grounded:OnHide()
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- shows the given inset "listInset", "bindInset", "helpInset"
function grounded:ShowInset(inset)
    for _,available in ipairs(insets) do
        if grounded[available] then
            if available==inset then
                grounded[inset]:Show()
                grounded[inset]:Update()
            else
                grounded[available]:Hide()
            end
        end
    end
end

-- returns the name and icon of a spell or item on the cursor
function grounded:GetCursorInfo()
    local cursorType,itemID,_,spellID = GetCursorInfo()
    if cursorType=="item" then
        local name,_,_,_,_,_,_,_,_,icon = C_Item.GetItemInfo(itemID)
        return name,icon
    elseif cursorType=="spell" then
        local name,_,icon = getSpellInfo(spellID)

        -- some covenant spells don't support @cursor unless you include their subtext, such as
        -- /cast [@cursor] Wild Spirits(Night Fae). on non-classic clients, add all subtexts just to
        -- be safe. (don't do this on classic because then it would always use the rank of the
        -- spell when the bind was made.)
        if not CLASSIC_CLIENT then
            local subtext = getSpellSubtext(spellID)
            if subtext and subtext~="" then
                name = name.."("..subtext..")"
            end
        end

        return name,icon
    end
end

--[[ listInset ]]

-- updates the listInset with the list of existing binds
function grounded.listInset:Update()
    local buttons = self.scrollFrame.content.buttons
    for _,button in ipairs(buttons) do
        button:Hide()
    end
    for i=1,#grounded.savedBinds+1 do -- +1 for the new bind button
        if not buttons[i] then
            buttons[i] = CreateFrame("Button",nil,self.scrollFrame.content,"GroundedListButtonTemplate")
            buttons[i]:SetPoint("TOPLEFT",0,-(i-1)*48)
            buttons[i]:SetID(i)
        end
        local button = buttons[i]
        local isNewBindButton = i==(#grounded.savedBinds+1)
        if isNewBindButton then
            button.bind = nil
            button.bindIndex = nil
            button.icon:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
        else
            button.bind = grounded.savedBinds[i]
            button.bindIndex = i
            button.icon:SetTexture(button.bind[ICON_INDEX] or (getSpellTexture(button.bind[NAME_INDEX])) or (select(10,C_Item.GetItemInfo(button.bind[NAME_INDEX]))) or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.spellText:SetText(format("\124cffffd200%s:\124r %s",getSpellInfo(button.bind[NAME_INDEX]) and "Spell" or "Item",button.bind[NAME_INDEX]))
            button.bindText:SetText(format("\124cffffd200Bind:\124r %s",button.bind[BIND_INDEX]))
        end
        button.instructionsText:SetShown(isNewBindButton)
        button.spellText:SetShown(not isNewBindButton)
        button.bindText:SetShown(not isNewBindButton)
        button:Show()
    end
    self.scrollFrame.content:SetHeight((#grounded.savedBinds+1)*48)
    grounded:UpdateSecureButtons()
end

-- click of one of the list buttons
function grounded.listInset:ButtonOnClick()
    -- if something is on the cursor being dropped on a list button, treat it as a new bind
    if grounded.listInset:ButtonOnReceiveDrag() then
        return -- it was handled, leave
    end
    if self.bind then
        grounded.bindInset:SetBind(self.bind,self.bindIndex)
        grounded:ShowInset("bindInset")
    end
end

-- when one of the list buttons receives a drag (or something on cursor when list button clicked), treat it as a new bind
function grounded.listInset:ButtonOnReceiveDrag()
    local name,icon = grounded:GetCursorInfo()
    if name then
        ClearCursor()
        grounded.bindInset:SetBind({name,nil,icon})
        grounded:ShowInset("bindInset")
        return true
    end
end

-- if an item or spell is dragged/dropped onto an empty area of the list, treat it as if dropped onto a button
function grounded.listInset.clickCapture:OnClick()
    grounded.listInset:ButtonOnReceiveDrag()
end

-- click of red Okay panel button just closes window
function grounded.listInset.okButton:OnClick()
    grounded:Hide()
end

--[[ bindInset ]]

-- updates the bindInset with the bind loaded into bindInset.bind
function grounded.bindInset:Update()
    local bind = self.bind -- table of bind in progress {NAME_INDEX,BIND_INDEX,ICON_INDEX,DOWN_INDEX,UP_INDEX}
    local content = self.scrollFrame.content
    local anchorTo = content.bindFrame -- the last frame to anchor to
    local key = bind[BIND_INDEX] -- key being bound (can be nil)
    -- hide tiles that may be shown
    content.bindWarning:Hide()
    content.reservedWarning:Hide()
    content.toyWarning:Hide()
    content.buttonWarning:Hide()
    content.editFrame:Hide()
    content.macroFrame:Hide()
    -- update spellFrame: icon and name of spell/item
    content.spellFrame.icon:SetTexture(bind[ICON_INDEX] or (getSpellTexture(bind[NAME_INDEX])) or (select(10,C_Item.GetItemInfo(bind[NAME_INDEX]))) or "Interface\\Icons\\INV_Misc_QuestionMark")
    content.spellFrame.spellText:SetSize(0,44) -- make width unbounded so GetStringWidth after setting text gets a real width
    content.spellFrame.spellText:SetText(bind[NAME_INDEX])
    content.spellFrame.spellText:SetSize(min(208,content.spellFrame.spellText:GetStringWidth()),44) -- to keep text centered, but wrap if starts to exceed content width (including icon)
    -- update displayed key that's chosen to bind
    content.bindFrame.bindText:SetText(bind[BIND_INDEX] or "Undefined")
    -- don't allow [Enter], / or [Escape] keys (or whatever the open chat and game menu keys are) so user isn't "locked" out of doing stuff
    if key==GetBindingKey("OPENCHAT") or key==GetBindingKey("OPENCHATSLASH") or key==GetBindingKey("TOGGLEGAMEMENU") then
        content.reservedWarning:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
        content.reservedWarning:Show()
        anchorTo = content.reservedWarning
    elseif key and GetBindingAction(key) then -- display warning if key is already bound to something
        local action = GetBindingAction(key)
        if action and action~="" then
            content.bindWarning.warnText:SetText(format("This will override the binding for \124cffffffff%s\124r.",(_G["BINDING_NAME_"..action] or action)))
            content.bindWarning:Show()
            anchorTo = content.bindWarning
        end
    end
    -- if not on classic clients, display warning if this is a toy (doesn't cast @cursor)
    if not CLASSIC_CLIENT then
        local itemID = (select(2,C_Item.GetItemInfo(bind[NAME_INDEX])) or ""):match("item:(%d+)")
        if itemID and tonumber(itemID) and C_ToyBox.GetToyInfo(tonumber(itemID)) then
            content.toyWarning:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
            anchorTo = content.toyWarning
            content.toyWarning:Show()
        end
    end
    -- display warning if key is a mouse button (in practice it doesn't work well)
    if key and key:lower():match("button") then
        content.buttonWarning:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
        anchorTo = content.buttonWarning
        content.buttonWarning:Show()
    end
    -- next display editFrame for a button to edit macros, and macroFrame for "expanded" edit options
    if bind[UP_INDEX] or bind[DOWN_INDEX] then
        content.macroFrame:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
        anchorTo = content.macroFrame
        content.macroFrame:Show()
        content.macroFrame.downEditBox.EditBox:SetText(bind[DOWN_INDEX])
        content.macroFrame.upEditBox.EditBox:SetText(bind[UP_INDEX])
    else
        content.editFrame:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
        anchorTo = content.editFrame
        content.editFrame:Show()
    end
    -- update red panel buttons
    grounded.bindInset:UpdatePanelButtons()
    -- finally anchor the padding to what's left
    content.paddingFrame:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT")
end

-- update the save and unbind button states
function grounded.bindInset:UpdatePanelButtons()
    local bind = self.bind
    local content = self.scrollFrame.content
    local key = bind[BIND_INDEX]
    -- evaluate save button
    local enableSave = true -- assume save is enabled until proven otherwise
    local downText = self.scrollFrame.content.macroFrame.downEditBox.EditBox:GetText()
    local upText = self.scrollFrame.content.macroFrame.upEditBox.EditBox:GetText()
    if content.macroFrame:IsShown() and (not downText or downText:len()==0 or not upText or upText:len()==0) then
        enableSave = false -- disable if either down or up macros are empty and macroFrame is shown
    end
    if not bind[BIND_INDEX] or bind[BIND_INDEX]:len()==0 then
        enableSave = false -- disable if no key bind defined
    end
    if content.reservedWarning:IsShown() then
        enableSave = false -- disable if key bind is a reserved key
    end
    self.saveButton:SetEnabled(enableSave)
    -- unbind button always enabled if there's a bindIndex
    self.unbindButton:SetEnabled(self.bindIndex and true)
end

-- bind is a table ({name,key,icon,down,up}) copied to bindInset along with the index if an existing bind
function grounded.bindInset:SetBind(bind,index)
    assert(type(bind)=="table" and #bind>0,"SetBind expects a bind table")
    self.bind = CopyTable(bind)
    self.bindIndex = index
end

-- click of red Cancel panel button returns to the listInset without saving anything
function grounded.bindInset.cancelButton:OnClick()
    grounded:ShowInset("listInset")
end

-- clicking the save button will either update the existing bind or add the new one to grounded.savedBinds
function grounded.bindInset.saveButton:OnClick()
    local bind = self:GetParent().bind
    local index = self:GetParent().bindIndex

    if not bind[ICON_INDEX] then -- for 1.0 binds, add icon if none defined
        bind[ICON_INDEX] = (getSpellTexture(bind[NAME_INDEX])) or (select(10,C_Item.GetItemInfo(bind[NAME_INDEX])))
    end

    local macroFrame = grounded.bindInset.scrollFrame.content.macroFrame
    if macroFrame:IsShown() then -- macro editboxes are shown, save the contents of the editboxes to the bind
        bind[DOWN_INDEX] = macroFrame.downEditBox.EditBox:GetText()
        bind[UP_INDEX] = macroFrame.upEditBox.EditBox:GetText()
    else -- macro editboxes aren't shown, remove any old macrotexts defined
        bind[DOWN_INDEX] = nil
        bind[UP_INDEX] = nil
    end

    assert(type(bind)=="table" and bind[NAME_INDEX] and bind[BIND_INDEX],format("Bind is not properly defined: %s (%s)",bind[NAME_INDEX] or "nil",bind[BIND_INDEX] or "nil"))


    if index then
        grounded.savedBinds[index] = CopyTable(bind)
    else
        table.insert(grounded.savedBinds,CopyTable(bind))
    end
    grounded:ShowInset("listInset")
end

-- clicking the unbind button will remove the currently opened binding
function grounded.bindInset.unbindButton:OnClick()
    local index = self:GetParent().bindIndex
    if index and grounded.savedBinds[index] then
        table.remove(grounded.savedBinds,index)
    end
    grounded:ShowInset("listInset")
end

-- while bindInset is on screen, this will capture keystroke/button clicks for binding
function grounded.bindInset.keyCapture:OnKeyDown(key)
    -- if ESC key hit, leave bind mode and return to list
    if key==GetBindingKey("TOGGLEGAMEMENU") then
        grounded.bindInset.cancelButton:Click()
        return
    end

    if key=="LALT" or key=="RALT" or key=="ALT" then
        return -- do nothing if pressing ALT, wait for another key
    elseif key=="LSHIFT" or key=="RSHIFT" or key=="SHIFT" then
        return -- do nothing if pressing SHIFT, wait for another key
    elseif key=="LCTRL" or key=="RCTRL" or key=="CTRL" then
        return -- do nothing if pressing CTRL, wait for another key
    elseif key=="LMETA" or key=="RMETA" or key=="META" then
        return -- do nothing if pressing META, wait for another key
    end

    -- if reached here, a non-modifier key was hit, attach modifiers
    local bind = IsAltKeyDown() and "ALT-" or ""
    bind = bind .. (IsControlKeyDown() and "CTRL-" or "")
    bind = bind .. (IsShiftKeyDown() and "SHIFT-" or "")
    bind = bind .. (IsMetaKeyDown() and "META-" or "")
    bind = bind .. key

    grounded.bindInset.bind[BIND_INDEX] = bind
    grounded.bindInset:Update()
end

-- click of "Edit Bind's Macros" button fills the down/up macros and displays them for editing
function grounded.bindInset.scrollFrame.content.editFrame.editButton:OnClick()
    local name = grounded.bindInset.bind[NAME_INDEX]
    grounded.bindInset.bind[DOWN_INDEX] = format(DOWN_TEMPLATE,name)
    grounded.bindInset.bind[UP_INDEX] = format(UP_TEMPLATE,name)
    grounded.bindInset:Update()
end

-- click of "Reset Bind's Macros" button removes the down/up macros and hides them
function grounded.bindInset.scrollFrame.content.macroFrame.resetButton:OnClick()
    grounded.bindInset.bind[DOWN_INDEX] = nil
    grounded.bindInset.bind[UP_INDEX] = nil
    grounded.bindInset:Update()
end

--[[ secure stuff: where the magic happens ]]

local secureButtons = {} -- button pool of secure buttons

-- returns an available secure button, creating a new one if needed
function grounded:GetSecureButton()
    for _,button in ipairs(secureButtons) do
        if not button.isUsed then
            button.isUsed = true
            return button
        end
    end
    -- if reached here, no available existing button, create a new one
    local buttonName = "GroundedSecureButton"..(#secureButtons)
    local button = CreateFrame("Button",buttonName,nil,"SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown","AnyUp")
    button:SetAttribute("type","macro")
    if not CLASSIC_CLIENT then
        button:SetAttribute("pressAndHoldAction",true)
        button:SetAttribute("typerelease","macro")
    end
    -- on key down, cast normally so reticle appears; on key up, cast @cursor
    SecureHandlerWrapScript(button,"OnClick",button,[[
        if down then
            self:SetAttribute("macrotext",self:GetAttribute("macrotextDown"))
        else
            self:SetAttribute("macrotext",self:GetAttribute("macrotextUp"))
        end
    ]])
    -- add it to the pool
    button.isUsed = true
    tinsert(secureButtons,button)
    return button -- and return it
end

-- creates/updates buttons for each defined bind and sets it to the spell and key from savedvars
function grounded:UpdateSecureButtons()
    -- if attempting to update bindings during combat, setup a frame to wait until combat ends
    -- and try again. (note this isn't using the main PLAYER_REGEN_ENABLED event because that
    -- event is only active while the window on screen. The goal is for no events to be registered
    -- beyond PLAYER_LOGIN in the 99.99% of sessions that this window is never summoned.
    if InCombatLockdown() then
        if not grounded.inCombatFrame then
            grounded.inCombatFrame = grounded.inCombatFrame or CreateFrame("Frame")
            grounded.inCombatFrame:SetScript("OnEvent",function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                grounded:UpdateSecureButtons()
            end)
        end
        -- register to listen for combat ending
        grounded.inCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return -- and leave; we'll be back when combat ends
    end
    -- clear any existing bindings
    for _,button in ipairs(secureButtons) do
        ClearOverrideBindings(button)
        button.isUsed = false
    end
    -- go through and set all bindings, creating buttons as needed
    for index,bind in ipairs(grounded.savedBinds) do
        local button = grounded:GetSecureButton()
        local name = bind[NAME_INDEX] or ""
        button:SetAttribute("macrotextDown",bind[DOWN_INDEX] or format(DOWN_TEMPLATE,name))
        button:SetAttribute("macrotextUp",bind[UP_INDEX] or format(UP_TEMPLATE,name))
        SetOverrideBindingClick(button,true,bind[BIND_INDEX],button:GetName())
    end
end
