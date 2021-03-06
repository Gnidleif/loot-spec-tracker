---- LOGIC SECTION
--- Namespaces
local this = CreateFrame('frame')

--- Variables
local UIConfig
this.specs = {} -- table containing available specs where [name] = id
this.instances = {} -- table containing available instances where [tier][type][name] = id
this.encounters = {} -- table containing all available instance encounters where [name] = {mode, id}
this.functions = {} -- table containing exported functions where [name] = func

--- Exported functions
--[[
  These are all stored in the this.functions table and are called by the user through the mock 'CLI'
]]
this.functions['help'] = function()
    print('/lsd help - brings up this help')
    print('/lsd toggle - hides or shows the main widget')
end

this.functions['toggle'] = function()
    UIConfig:SetShown(not UIConfig:IsShown())
end

this.functions['spec'] = function(...)
    args = {...}
    this:set_spec(args[2])
end

--- Functions
function this:set_spec(...)
    local args = {...}
    local name = args[1]
    if (name == 'auto') then
        SetLootSpecialization(0)
        return
    end
    local id = this.specs[name]
    if (id) then
        SetLootSpecialization(id)
    end
end

-- init_specializations iterate the number of available specs for the active char and adds each ID to the list of specs using the spec name as a key
function this:init_specializations()
    local i = 0
    while (i < GetNumSpecializations()) do
        local id, name = GetSpecializationInfo(i+1)
        this.specs[string.lower(name)] = id
        i = i + 1
    end
end

function this:distance2d_squared(x1, y1, x2, y2)
    return abs(x2 - x1)^2 + abs(y2 - y1)^2
end

-- identify_encounter finds the encounter that's currently closest to the player, if no encounter is close to the player nil is returned
function this:identify_encounter()
    SetMapToCurrentZone()
    local px, py = GetPlayerMapPosition('player')
    local i, distance_lowest, distance_current = 1, 1, 1
    local x, y, _, _, _, id = EJ_GetMapEncounter(i)
    local closest_encounter
    while (id) do
        distance_current = this.distance2d_squared(px, py, x, 1-y)
        if distance_current < distance_lowest then
            distance_lowest = distance_current
            closest_encounter = id
        end
        i = i + 1
        x, y, _, _, _, id = EJ_GetMapEncounter(i)
    end
    return this.encounters[closest_encounter]
end

function this:init_encounters(instance)
    local i = 1
    local name, _, id = EJ_GetEncounterInfoByIndex(instance, i)
    while (id) do
        this.encounters[id] = 'none'
        i = i + 1
        name, _, id = EJ_GetEncounterInfoByIndex(instance, i)
    end
end

-- init_instances iterates every available instance of every available tier and adds them as lists of lists in the this.instances table 
function this:init_instances()
    -- by_tier is a local function used to iterate every dungeon or raid of a given tier and return them as a table with the stored ID as a value and the name as a key
    local by_tier = function(tier, is_raid)
        -- sets the current tier to i in order to retrieve relevant instances
        EJ_SelectTier(tier)
        local instances = {}
        local i = 1
        local id, name = EJ_GetInstanceByIndex(i, is_raid)
        while (id) do
            instances[name] = id
            this.init_encounters(id)
            i = i + 1
            id, name = EJ_GetInstanceByIndex(i, is_raid)
        end
        return instances
    end
    -- for loop that iterates each tier
    for i = 1, EJ_GetNumTiers() do
        local tier = EJ_GetTierInfo(i)
        this.instances[tier] = {
            raids = by_tier(i, true),
            dungeons = by_tier(i, false),
        }
    end
    -- resets the selected tier to last tier to avoid any bugs
    EJ_SelectTier(EJ_GetNumTiers())
end

local function SlashCommandHandler(cmd)
    if (#cmd == 0) then
        this.functions['help']()
        return
    end
    -- emulates a CLI by finding characters and adding them to a list of args which are then sent to the functions
    cmd = cmd:lower()
    local args = {}
    for w in cmd:gmatch('%S+') do
        table.insert(args, w)
    end
    -- if args[1] exists, it's always the name of the function
    local func = this.functions[args[1]]
    if (func) then
        func(args)
    else
        -- defaults to calling the help function if user tries to call non-existant function
        this.functions['help']()
    end
end

--- Event handling
this:RegisterEvent('PLAYER_LOOT_SPEC_UPDATED')
this:RegisterEvent('PLAYER_LOGIN')
this:RegisterEvent('PLAYER_REGEN_DISABLED')
this:RegisterEvent('PLAYER_REGEN_ENABLED')
this:SetScript('OnEvent', function(self, event, ...)
    if event == 'PLAYER_LOOT_SPEC_UPDATED' then
        local id = GetLootSpecialization()
        if (id == 0) then
            SendSystemMessage('Loot Specialization set to: Auto')
        end
    elseif event == 'PLAYER_LOGIN' then
        this.old_loot_spec = GetLootSpecialization()
        this:init_specializations()
        this:init_instances()
        this:init_UI()
        UIConfig:Show()
    elseif event == 'PLAYER_REGEN_DISABLED' then
        SendSystemMessage('Entered combat...')
        mode = this.identify_encounter()
        if (not mode or mode == 'none') then
            return
        end
        this.old_loot_spec = GetLootSpecialization()
        this.set_spec(mode)
    elseif event == 'PLAYER_REGEN_ENABLED' then
        if this.old_loot_spec != GetLootSpecialization() then
            this.SetLootSpecialization(this.old_loot_spec)
        end
        SendSystemMessage('Exited combat...')
    end
end)

--- Slash recognition
SLASH_LOOTSPECDESIGNATOR1 = '/lsd'
SlashCmdList['LOOTSPECDESIGNATOR'] = SlashCommandHandler

-- fast command to reload ui
SLASH_RELOADUI1 = '/rl'
SlashCmdList.RELOADUI = ReloadUI

-- disables turning when pressing arrow keys (used for debugging)
for i = 1, NUM_CHAT_WINDOWS do
  _G['ChatFrame'..i..'EditBox']:SetAltArrowKeyMode(false)
end

---- USER INTERFACE SECTION
-- init-UI initializes all of the UI elements
function this:init_UI(self)
    local w = (65 * (GetNumSpecializations() + 1)) + 16
    UIConfig = CreateFrame('Frame', 'LootSpecDesignator', UIParent, 'BasicFrameTemplateWithInset')
    UIConfig:SetSize(w, 80) -- width needs to change depending on amount of specs
    UIConfig:SetPoint('CENTER', UIParent, 'CENTER')
    UIConfig:SetMovable(true)
    UIConfig:EnableMouse(true)
    UIConfig:RegisterForDrag('LeftButton')
    UIConfig:SetScript('OnDragStart', UIConfig.StartMoving)
    UIConfig:SetScript('OnDragStop', UIConfig.StopMovingOrSizing)

    UIConfig.title = UIConfig:CreateFontString(nil, 'OVERLAY')
    UIConfig.title:SetFontObject('GameFontHighlight')
    UIConfig.title:SetPoint('LEFT', UIConfig.TitleBg, 'LEFT', 5, 0)
    UIConfig.title:SetText('Loot Spec Designator')

    local create_spec_button = function(parent, key, text, spacing)
        local b = CreateFrame('Button', nil, parent, 'GameMenuButtonTemplate')
        b:SetPoint('LEFT', parent, 'RIGHT', spacing, 0)
        b:SetSize(60, 40)
        b:SetText(text)
        b:SetNormalFontObject('GameFontNormalLarge')
        b:SetHighlightFontObject('GameFontHighlightLarge')
        b:SetScript('OnClick', function(self, args, ...)
            this:set_spec(key)
        end)
        return b
    end

    UIConfig.btns = {}
    UIConfig.btns['auto'] = create_spec_button(UIConfig, 'auto', 'Auto', 0)
    UIConfig.btns['auto']:SetPoint('LEFT', UIConfig, 'LEFT', 8, -10)
    local parent = UIConfig.btns['auto']
    for k, v in pairs(this.specs) do
        UIConfig.btns[k] = create_spec_button(parent, k, v, 5)
        parent = UIConfig.btns[k]
    end
end