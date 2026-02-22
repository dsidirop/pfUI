pfUI:RegisterModule("focus", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  pfUI.uf.focus = pfUI.uf:CreateUnitFrame("Focus", nil, C.unitframes.focus, .2)
  pfUI.uf.focus:UpdateFrameSize()
  pfUI.uf.focus:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
  UpdateMovable(pfUI.uf.focus)
  pfUI.uf.focus:Hide()

  pfUI.uf.focustarget = pfUI.uf:CreateUnitFrame("FocusTarget", nil, C.unitframes.focustarget, .2)
  pfUI.uf.focustarget:UpdateFrameSize()
  pfUI.uf.focustarget:SetPoint("BOTTOMLEFT", pfUI.uf.focus, "TOP", 0, 10)
  UpdateMovable(pfUI.uf.focustarget)
  pfUI.uf.focustarget:Hide()
end)

-- register focus emulation commands for vanilla
if pfUI.client > 11200 then return end

-- Helper: set focus frame to a GUID
local function SetFocusByGUID(guid)

  local uf_focus = pfUI.uf.focus
  uf_focus.id = ""
  uf_focus.label = guid
  uf_focus.unitname = nil

  local uf_focustarget = pfUI.uf.focustarget
  if uf_focustarget then
    uf_focustarget.id = ""
    uf_focustarget.label = guid .. "target"
    uf_focustarget.unitname = nil
  end
end

-- Helper: set focus frame by name (fallback, no Nampower)
local function SetFocusByName(name)
  name = strlower(name)

  local uf_focus = pfUI.uf.focus
  uf_focus.id = nil
  uf_focus.label = nil
  uf_focus.unitname = name

  local uf_focustarget = pfUI.uf.focustarget
  if uf_focustarget then
    uf_focustarget.id = nil
    uf_focustarget.label = nil
    uf_focustarget.unitname = name .. "target"
  end
end

SLASH_PFFOCUS1, SLASH_PFFOCUS2 = '/focus', '/pffocus'
function SlashCmdList.PFFOCUS(desiredTarget)
  if not pfUI.uf or not pfUI.uf.focus then return end

  if desiredTarget ~= nil and type(desiredTarget) ~= "string" then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  desiredTarget = desiredTarget or "" -- unify nil and "" into a single case

  local _, guid = nil, nil -- try guid-based focus (turtle wow native)

  if UnitExists then
    -- modern mechanism with nampower
    if desiredTarget == "" then
      _, guid = UnitExists("target")
    else
      local _, guidOriginal = UnitExists("target")

      TargetByName(desiredTarget, true)

      _, guid = UnitExists("target")

      if guidOriginal ~= guid then
        -- note that even if no target was initially selected the TargetLastTarget() call will still do
        -- the right thing and unselect the current target thus reverting back to no-target as intended
        TargetLastTarget()
      end
    end

    if guid == "0x0000000000000000" then
      -- normalize the guid in all cases
      guid = nil
    end

    if guid then
      SetFocusByGUID(guid)
    end

    return
  end

  -- legacy mechanism  without nampower
  local unitName = UnitName(desiredTarget == "" and "target" or desiredTarget)
  if unitName then
    SetFocusByName(name)
  end
end

SLASH_PFCLEARFOCUS1, SLASH_PFCLEARFOCUS2 = '/clearfocus', '/pfclearfocus'
function SlashCmdList.PFCLEARFOCUS()
  if pfUI.uf and pfUI.uf.focus then
    pfUI.uf.focus.unitname = nil
    pfUI.uf.focus.label = nil
    pfUI.uf.focus.id = nil
  end

  if pfUI.uf and pfUI.uf.focustarget then
    pfUI.uf.focustarget.unitname = nil
    pfUI.uf.focustarget.label = nil
    pfUI.uf.focustarget.id = nil
  end
end

local function ProperFocusCast(properCastSpell, msg)
  if not pfUI.uf.focus or not pfUI.uf.focus:IsShown() then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
  local hasGUID = focusGUID and focusGUID ~= "" and focusGUID ~= "0x0000000000000000"
  local focusGUID = pfUI.uf.focus.label

  -- guid-based cast (nampower) - no target toggle needed
  if hasGUID and not func then
    properCastSpell(msg, focusGUID)
    return
  end

  -- for lua functions with guid: short target swap via guid
  if hasGUID and func then
    local _, currentGUID = UnitExists("target")
    local isPlayer = UnitIsUnit("target", "player")

    TargetUnit(focusGUID)
    local _, newGUID = UnitExists("target")

    if newGUID ~= focusGUID then
      -- could not target focus, restore and fail
      if currentGUID and currentGUID ~= "0x0000000000000000" then
        TargetUnit(currentGUID)
      elseif isPlayer then
        TargetUnit("player")
      else
        TargetLastTarget()
      end

      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end

    func()

    if currentGUID and currentGUID ~= "0x0000000000000000" then
      TargetUnit(currentGUID)
    elseif isPlayer then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
  end

  -- fallback: name-based target swap (no nampower / no guid)
  local player = UnitIsUnit("target", "player")
  local focusId = pfUI.uf.focus.id
  local focusLabel = pfUI.uf.focus.label
  local unitname = ""
  local skiptarget = false

  if focusLabel and focusId and
    UnitIsUnit("target", focusLabel .. focusId) then
    skiptarget = true
  else
    pfScanActive = true
    if focusGUID and focusId then
      unitname = UnitName(focusGUID .. focusId)
      TargetUnit(focusGUID .. focusId)
    else
      unitname = pfUI.uf.focus.unitname
      TargetByName(pfUI.uf.focus.unitname, true)
    end

    if strlower(UnitName("target") or "") ~= strlower(unitname or "") then
      pfScanActive = nil
      TargetLastTarget()
      UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
      return
    end
  end

  if func then
    func()
  else
    properCastSpell(msg)
  end

  if skiptarget == false then
    pfScanActive = nil
    if player then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
  end
end

-- will deliberately prefer using CastSpellByNameNoQueue if available   the no-queue
-- behaviour forces a spell cast to never queue to avoid nasty unnecessary overhead
-- (even if your settings would normally queue)   this clearly is the most reasonable
-- default behaviour for practical focus-casting-scenarios in high-intensity situations
-- 
-- if you prefer to allow queueing for focus-casts you can use the /standardcastfocus command
-- which uses the regular CastSpellByName and thus respects the users global queueing settings
--
-- for insta-cast use-cases you might want to consider invoking /run SpellStopCasting() first 
SLASH_PFCASTFOCUS1, SLASH_PFCASTFOCUS2 = '/castfocus', '/pfcastfocus'
function SlashCmdList.PFCASTFOCUS(msg)
  ProperFocusCast(CastSpellByNameNoQueue or CastSpellByName, msg)
end

-- this flavour of focus-casting uses the traditional CastSpellByName which by default doesnt
-- use queueing (unless the user changes the associated setting globally to force it to) use this
-- flavor when you are sure you dont want to interrupt any current spell being cast before the focus-cast
SLASH_PFSTANDARDCASTFOCUS1, SLASH_PFSTANDARDCASTFOCUS2 = '/standardcastfocus', '/pfstandardcastfocus'
function SlashCmdList.PFSTANDARDCASTFOCUS(msg)
  ProperFocusCast(CastSpellByName, msg)
end

SLASH_PFSWAPFOCUS1, SLASH_PFSWAPFOCUS2 = '/swapfocus', '/pfswapfocus'
function SlashCmdList.PFSWAPFOCUS()
  if not pfUI.uf or not pfUI.uf.focus then return end

  local _, guid = nil, nil
  if UnitExists then
    _, guid = UnitExists("target")
  end

  if guid and guid ~= "0x0000000000000000" then
    local oldGUID = pfUI.uf.focus.label

    SetFocusByGUID(guid)

    -- Target old focus if we had one
    if oldGUID and oldGUID ~= "" and oldGUID ~= "0x0000000000000000" then
      TargetUnit(oldGUID)
    end
  else
    -- Fallback: name-based swap
    local oldunit = UnitExists("target") and strlower(UnitName("target") or "")
    if oldunit and pfUI.uf.focus.unitname then
      TargetByName(pfUI.uf.focus.unitname, true)
      pfUI.uf.focus.unitname = oldunit
    end
  end
end