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

SLASH_PFFOCUS1, SLASH_PFFOCUS2 = '/focus', '/pffocus'
function SlashCmdList.PFFOCUS(msg)
  if not pfUI.uf or not pfUI.uf.focus then return end

  if msg ~= nil and type(msg) ~= "string" then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  local _, guid = nil, nil -- try guid-based focus (turtle wow native)

  if msg == "" then
    _, guid = UnitExists("target")
  else    
    local _, guidOriginal = UnitExists("target")

    TargetByName(msg, true)

    _, guid = UnitExists("target")

    if guidOriginal ~= guid then
      TargetLastTarget()
    end
  end

  if guid == "0x0000000000000000" then -- normalize the guid
    guid = nil
  end

  if guid then
    pfUI.uf.focus.id = "" -- guid-based focus (works with unitframes api)
    pfUI.uf.focus.unitname = nil

    if pfUI.uf.focustarget then -- update focustarget frame
      pfUI.uf.focustarget.label = guid .. "target"
    end

  elseif msg == "" then -- no target and no msg - clear focus
    local unitName = UnitName("target")
    if unitName then
      pfUI.uf.focus.id = ""
      pfUI.uf.focus.label = nil
      pfUI.uf.focus.unitname = strlower(unitName)
    else -- if there is no target currently selected then clear focus completely
      pfUI.uf.focus.id = nil
      pfUI.uf.focus.label = nil
      pfUI.uf.focus.unitname = nil
    end
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

SLASH_PFCASTFOCUS1, SLASH_PFCASTFOCUS2 = '/castfocus', '/pfcastfocus'
function SlashCmdList.PFCASTFOCUS(msg)
  if not pfUI.uf.focus or not pfUI.uf.focus:IsShown() then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
  
  -- Check if we have GUID-based focus
  local focusGUID = pfUI.uf.focus.label
  local hasGUID = focusGUID and focusGUID ~= ""

  local properCastSpell = CastSpellByNameNoQueue or CastSpellByName
  
  -- Nampower with NEW unitStr targeting support (no target toggle needed!)
  if hasGUID then
    if func then
      -- For lua functions, we still need target toggle (function might use UnitName("target") etc)
      local _, currentGUID = nil, nil
      if UnitExists then
        _, currentGUID = UnitExists("target")
      end
      local player = UnitIsUnit("target", "player")
      
      -- Target focus by GUID
      TargetUnit(focusGUID)
      
      -- Verify we actually targeted the focus
      local _, targetGUID = nil, nil
      if UnitExists then
        _, targetGUID = UnitExists("target")
      end
      
      if targetGUID ~= focusGUID then
        -- Restore original target and fail
        if currentGUID then
          TargetUnit(currentGUID)
        elseif player then
          TargetUnit("player")
        else
          TargetLastTarget()
        end
        UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
        return
      end
      
      -- Execute function
      func()
      
      -- Restore original target
      if currentGUID then
        TargetUnit(currentGUID)
      elseif player then
        TargetUnit("player")
      else
        TargetLastTarget()
      end
    else
      -- Direct spell cast with GUID - NO TARGET TOGGLE! 🎉
      properCastSpell(msg, focusGUID)
    end
    
    return
  end
  
  -- Fallback: Classic target-swapping method (name-based or GUID-based)
  local player = UnitIsUnit("target", "player")
  local focusId = pfUI.uf.focus.id
  local unitname = ""
  local skiptarget = false

  if focusGUID and UnitIsUnit("target", focusGUID .. focusId) then
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

    if strlower(UnitName("target")) ~= strlower(unitname) then
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

SLASH_PFSWAPFOCUS1, SLASH_PFSWAPFOCUS2 = '/swapfocus', '/pfswapfocus'
function SlashCmdList.PFSWAPFOCUS()
  if not pfUI.uf or not pfUI.uf.focus then return end

  -- Try GUID-based swap
  local _, guid = nil, nil
  if UnitExists then
    _, guid = UnitExists("target")
  end
  
  if guid then
    -- Save old focus GUID
    local oldlabel = pfUI.uf.focus.label or ""
    local oldid = pfUI.uf.focus.id or ""
    
    -- Set new focus to current target
    pfUI.uf.focus.unitname = nil
    pfUI.uf.focus.label = guid
    pfUI.uf.focus.id = ""
    
    -- Update focustarget
    if pfUI.uf.focustarget then
      pfUI.uf.focustarget.unitname = nil
      pfUI.uf.focustarget.label = guid .. "target"
      pfUI.uf.focustarget.id = ""
    end
    
    -- Target old focus
    if oldlabel and oldlabel ~= "" then
      TargetUnit(oldlabel .. oldid)
    end
  else
    -- Fallback: name-based swap
    local oldunit = UnitExists("target") and strlower(UnitName("target"))
    if oldunit and pfUI.uf.focus.unitname then
      TargetByName(pfUI.uf.focus.unitname)
      pfUI.uf.focus.unitname = oldunit
    end
  end
end
