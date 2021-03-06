-------------------------------------------------------------------------------
--- Dialog Control.
-- Functions for user interface dialogues
-- @module rinLibrary.K400Dialog
-- @author Darren Pearson
-- @author Merrick Heley
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local string = string
local tonumber = tonumber
local type = type
local math = math
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table = table
local bit32 = require "bit"

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, depricated)

local dialogRunning = 0
local getKeyPressed = 0
local getKeyState = ''
local editing = false

local sEditVal = ' '        -- default edit value for sEdit()
local sEditIndex = 1        -- starting index for sEdit()
local sEditKeyTimer = 0     -- counts time since a key pressed for sEdit() - in scrUpdTm increments
local sEditKeyTimeout = 4   -- number of counts before starting a new key in sEdit()

local scrUpdTm = 0.5        -- screen update frequency in Sec
local blinkOff = false      -- blink cursor for string editing

local msgDisp = false	    -- message is being displayed by dispMsg function
local msgTimer = nil		-- timer for user message display

-------------------------------------------------------------------------------
-- Is a message currently being displayed?
-- @return true iff a message is displayed
function _M.messageDisplayed()
    return msgDisp
end

-------------------------------------------------------------------------------
-- Is a dialog currently being displayed?
-- @return true iff a dialog is displayed
function _M.dialogRunning()
    return dialogRunning ~= 0
end

function _M.abortDialog()
    dialogRunning = dialogRunning - 1
    if dialogRunning < 0 then
        dialogRunning = 0
    end
end

function _M.startDialog()
    dialogRunning = dialogRunning + 1
    private.bumpIdleTimer()
end

local function getKeyCallback(key, state)
    getKeyPressed = key
    getKeyState = state
    return true
end

local function endDisplayMessage()
	if msgDisp then
        msgDisp = false
	    _M.system.timers.removeTimer(msgTimer)
        msgTimer = nil
        _M.restoreBot()
    end
end

-------------------------------------------------------------------------------
-- Called to display a message to the screen for a time
-- @param msg message displayed on bottom left LCD
-- @param t number of seconds to display message (can be fractional; e.g. 2.125)
-- @param units optional units to display
-- @param unitsOther optional other units to display
function _M.displayMessage(msg, t, units, unitsOther)
	local u = units or 0			-- optional units defaults to none
	local uo = unitsOther or 0		-- optional other units defaults to none
    local t = t or 0.5

    endDisplayMessage()
	if msg and (t > 0) then		
		msgDisp = true
		_M.saveBot()
		_M.writeBotLeft(msg)			-- display message
		_M.writeBotUnits(u,uo)			-- display optional units
		msgTimer = _M.system.timers.addTimer(0, t, endDisplayMessage)
	end
end

-------------------------------------------------------------------------------
-- Called to display a message to the screen for a time and waits for it to finish
-- @param msg message displayed on bottom left LCD
-- @param t number of seconds to display message (can be fractional; e.g. 2.125)
-- @param units optional units to display
-- @param unitsOther optional other units to display
function _M.displayMessageWait(msg, t, units, unitsOther)
   _M.displayMessage(msg,t,units,unitsOther)
   while msgDisp do
       _M.system.handleEvents()
   end
end

-------------------------------------------------------------------------------
-- Called to get a key from specified key group
-- @param keyGroup keyGroup.all is default group
-- @return key (KEY_), state ('short','long','up')
function _M.getKey(keyGroup)
    local keyGroup = keyGroup or _M.keyGroup.all
    local f = keyGroup.callback

    _M.setKeyGroupCallback(keyGroup, getKeyCallback)

    getKeyState = ''
    getKeyPressed = nil
    _M.startDialog()
    while _M.dialogRunning() and _M.app.running and getKeyState == '' do
        _M.system.handleEvents()
    end
    _M.abortDialog()
    _M.setKeyGroupCallback(keyGroup, f)

    return getKeyPressed, getKeyState

 end

-------------------------------------------------------------------------------
-- Check to see if editing routines active
-- @return true of editing false otherwise
function _M.isEditing()
   return editing
end

-------------------------------------------------------------------------------
-- Change the screen update frequency for the next dialog presented.
-- @param s The update frequency in seconds to set for next time
-- @return The previous update frequency
function _M.setScreenUpdateFrequency(s)
    local old = scrUpdTm
    scrUpdTm = s or 0.5
    if scrUpdTm < .1 then
        scrUpdTm = .5
    end
    return old
end


-----------------------------------------------------------------------------------------------
-- Helper function that takes a string and a position and returns the character
-- at the specified position.  It modulo reduces its argument to the string's
-- length.
-- @param s String of legal characters
-- @param p Position in string
-- @return The relevant character
local function keyCharSelect(s, p)
    if s == nil then return nil end
    local z = math.fmod(p, #s)
    if z == 0 then z = #s end
    return s:sub(z, z)
end

-----------------------------------------------------------------------------------------------
-- This table defines the mapping from the numeric keys to alpha characters.
-- The first press results in the first character, the second the second and
-- so forth.
local keyMapping = {
    [_M.KEY_1] = "$/\\1",
    [_M.KEY_2] = "ABC2",
    [_M.KEY_3] = "DEF3",
    [_M.KEY_4] = "GHI4",
    [_M.KEY_5] = "JKL5",
    [_M.KEY_6] = "MNO6",
    [_M.KEY_7] = "PQRS7",
    [_M.KEY_8] = "TUV8",
    [_M.KEY_9] = "WXYZ9",
    [_M.KEY_0] = " 0"
}

-----------------------------------------------------------------------------------------------
-- return a character for the key pressed, according to the number of times it has been pressed
-- @param k key pressed
-- @param p number of times key has been pressed
-- @return letter, number or symbol character represented on the number key pad
-----------------------------------------------------------------------------------------------

function _M.keyChar(k, p)
    return keyCharSelect(keyMapping[k], p)
end

local function sTrim(s)       -- removes whitespace from strings
    return s:match'^%s*(.*%S)' or ''
end

-----------------------------------------------------------------------------------------------
-- Set the key timeout in terms of the number of blink half cycles
-- @param n The timeout
-- @return The previous timeout
function _M.setEditKeyTimout(n)
    local old = sEditKeyTimeout
    sEditKeyTimeout = n or 4
    if n < 2 then n = 4 end
    return old
end

local function blinkCursor()
--  used in sEdit() function below
    sEditKeyTimer = sEditKeyTimer + 1 -- increment key press timer for sEdit()
    local str
    local pre
    local suf
    local max = #sEditVal
    blinkOff = not blinkOff
    if blinkOff then
        pre = string.sub(sEditVal, 1, sEditIndex-1)
        if sEditIndex < max then
            suf = string.sub(sEditVal, sEditIndex+1, -1)
        else
            suf = ''
        end
        str = pre .. "_" .. suf
    else
        str = sEditVal
    end
--  print(str)  -- debug
    _M.writeBotLeft(str)
end

-------------------------------------------------------------------------------
-- Called to prompt operator to enter a string
-- @param prompt string displayed on bottom right LCD
-- @param def default value
-- @param maxLen maximum number of characters to include
-- @param units optional units to display
-- @param unitsOther optional other units to display
-- @return value and true if ok pressed at end

function _M.sEdit(prompt, def, maxLen, units, unitsOther)

    editing = true                  -- is editing occurring
    local key, state                -- instrument key values
    local pKey = nil                -- previous key pressed
    local presses = 0               -- number of consecutive presses of a key

    if def then                     -- if a string is supplied
        def = sTrim(def)            -- trim any whitespace
    end

    local default = def or ' '      -- default string to edit, if no default passed to function, default to one space
    sEditVal = tostring(default)    -- edit string
    local sLen = #sEditVal       -- length of string being edited
    sEditIndex = sLen               -- index in string of character being edited
    local ok = false                -- OK button was pressed to accept editing
    local strTab = {}               -- temporary table holding edited string characters
    local blink = false             -- cursor display variable
    local u = units or 0            -- optional units defaults to none
    local uo = unitsOther or 0      -- optional other units defaults to none

    endDisplayMessage()             -- abort any existing display prompt
    local cursorTmr = _M.system.timers.addTimer(scrUpdTm, 0, blinkCursor)  -- add timer to blink the cursor
    _M.saveBot()

    if sLen >= 1 then   -- string length should always be >= 1 because of 'default' assignment above
        for i=0,math.min(sLen, maxLen),1 do
            strTab[i] = string.sub(sEditVal, i, i)   -- convert the string to a table for easier character manipulation
        end
        --print('strTab = ' .. table.concat(strTab))  -- debug
    end
    sEditVal = table.concat(strTab);

    if def then         -- if a default string is given
        pKey = 'def'    -- give pKey a value so we start editing from the end
    end

    _M.writeBotRight(prompt)        -- write the prompt
    _M.writeBotLeft(sEditVal)    -- write the default string to edit
    _M.writeBotUnits(u,uo)          -- display optional units

    _M.startDialog()
    while editing and _M.app.running do
        key, state = _M.getKey(_M.keyGroup.keypad)  -- wait for a key press
        if sEditKeyTimer > sEditKeyTimeout then   -- if a key is not pressed for a couple of seconds
            pKey = 'timeout'                            -- ignore previous key presses and treat this as a different key
        end
        sEditKeyTimer = 0                        -- reset the timeout counter now a key has been pressed
        if not _M.dialogRunning() then    -- editing aborted so return default
            ok = false
           editing = false
           sEditVal = default
        elseif state == "short" then                            -- short key presses for editing
            if key >= _M.KEY_0 and key <= _M.KEY_9 then     -- keys 0 to 9 on the keypad
--              print('i:' .. sEditIndex .. ' l:' .. sLen)   -- debug
                if key == pKey then         -- if same as the previous key pressed
                    presses = presses + 1   -- add 1 to number of presses of this key
                else
                    presses = 1             -- otherwise reset presses to 1
                    if pKey and (sEditIndex >= sLen) and (strTab[sEditIndex] ~= " ") then     -- if not first key pressed
                        sEditIndex = sEditIndex + 1       -- new key pressed, increment the character position
                    end
                    pKey = key              -- remember the key pressed
                end
--              print('i:' .. sEditIndex)    -- debug
                strTab[sEditIndex] = _M.keyChar(key, presses)    -- update the string (table) with the new character
            --
            elseif (key == _M.KEY_DP) and (key ~= pKey) then        -- decimal point key (successive decimal points not allowed)
                if (pKey and (sEditIndex >= sLen)) or (strTab[sEditIndex] == " ") then    -- if not first key pressed and not space at end
                    sEditIndex = sEditIndex + 1           -- new key pressed, increment the character position
                end
                strTab[sEditIndex] = "."                 -- update the string (table) with the new character
                pKey = key                                  -- remember the key pressed
            --
            elseif key == _M.KEY_UP then                    -- up key, previous character
                sEditIndex = sEditIndex - 1               -- decrease index
                if sEditIndex < 1 then                       -- if at first character
                    sEditIndex = sLen                            -- go to last character
                end
                pKey = key                                  -- remember the key pressed
            --
            elseif key == _M.KEY_DOWN then          -- down key, next character
                sEditIndex = sEditIndex + 1       -- increment index
                if sEditIndex > sLen then            -- if at last character
                    if strTab[sLen] ~= " " then         -- and last character is not a space
                        if sLen < maxLen then               -- and length of string < maximum
                            sLen = sLen + 1                     -- increase length of string
                            strTab[sLen] = " "                  -- and add a space to the end
                        else                                -- string length = maximum
                            sEditIndex = 1                   -- go to the first character
                        end
                    else                                -- otherwise (last character is a space)
                        if sLen > 1 then                    -- as long as the string is more than 1 character long
                            strTab[sLen] = nil              -- delete the last character
                            sLen = sLen - 1                 -- decrease the length of the string
                            sEditIndex = 1               -- and go to the first character
                        end
                    end
                end
                pKey = key                                  -- remember the key pressed
            --
            elseif key == _M.KEY_PLUSMINUS then     -- plus/minus key - insert a character
                if sLen < maxLen then
                    sLen = sLen + 1                     -- increase the length of the string
                end
                for i = sLen, sEditIndex+1, -1 do
                    strTab[i] = strTab[i-1]             -- shuffle the characters along
                end
                strTab[sEditIndex] = " "             -- insert a space
                pKey = key                          -- remember the key pressed
            --
            elseif key == _M.KEY_OK then        -- OK key
                editing = false                      -- finish editing
                ok = true                           -- accept changes
            --
            elseif key == _M.KEY_CANCEL then    -- cancel key
                if sEditIndex < sLen then
                    for i = sEditIndex, sLen-1 do    -- delete current character
                        strTab[i] = strTab[i+1]         -- shuffle characters along
                    end
                end
                strTab[sLen] = nil                  -- clear last character
                sEditIndex = sEditIndex - 1   -- decrease length of string
                pKey = key                          -- remember the key pressed
            end
        elseif state == "long" then         -- long key press only for cancelling editing
            if key == _M.KEY_CANCEL then    -- cancel key
                sEditVal = default               -- reinstate default string
                editing = false                     -- finish editing
            end
        end
        if editing or ok then                       -- if editing or OK is selected
            sEditVal = table.concat(strTab)      -- update edited string
            sLen = #sEditVal
--          print('eVal = \'' .. sEditVal .. '\'')   -- debug
        end
    end
    _M.abortDialog()

    _M.restoreBot() -- restore previously displayed messages

    _M.system.timers.removeTimer(cursorTmr) -- remove cursor blink timer
    return sEditVal, ok                  -- return edited string and OK status
end

-------------------------------------------------------------------------------
-- Called to prompt operator to enter a value, numeric digits and '.' only
-- @param prompt string displayed on bottom right LCD
-- @param def default value
-- @param typ type of value to enter ('integer','number','passcode')
-- @param units optional units to display
-- @param unitsOther optional other units to display
-- @return value and true if ok pressed at end
function _M.edit(prompt, def, typ, units, unitsOther)

    local key, state
    local hide = false

    if typ == 'passcode' then
        typ = 'integer'
        hide = true
    end

    local def = def or ''
    if type(def) ~= 'string' then
         def = tostring(def)
     end

    local u = units or 0
    local uo = unitsOther or 0

    local editVal = def
    local editType = typ or 'integer'
    editing = true
    endDisplayMessage()
    _M.saveBot()
    _M.writeBotRight(prompt)
    if hide then
       _M.writeBotLeft(string.rep('+',#editVal))
    else
       _M.writeBotLeft(editVal)
    end
    _M.writeBotUnits(u, uo)

    local first = true

    local ok = false
    _M.startDialog()
    while editing and _M.app.running do
        key, state = _M.getKey(_M.keyGroup.keypad)
        if not _M.dialogRunning() then    -- editing aborted so return default
            ok = false
           editing = false
           sEditVal = def
        elseif state == 'short' then
            if key >= _M.KEY_0 and key <= _M.KEY_9 then
                if first then
                    editVal = tostring(key)
                else
                    editVal = editVal .. key
                end
                first = false
            elseif key == _M.KEY_DP and editType ~= 'integer' then
                if editType == 'number' then
                    if first or string.len(editVal) == 0 then
                       editVal = '0.'
                       first = false
                    elseif not string.find(editVal,'%.')  then
                       editVal = editVal .. '.'
                    end
                else
                   editVal = editVal .. '.'
                end
            elseif key == _M.KEY_OK then
                editing = false
                 if string.len(editVal) == 0 then
                    editVal = def
                 end
                ok = true
            elseif key == _M.KEY_CANCEL then
                if string.len(editVal) == 0 then
                    editVal = def
                    editing = false
                else
                    editVal = string.sub(editVal,1,-2)
                end
            end
        elseif state == 'long' then
            if key == _M.KEY_CANCEL then
                editVal = def
                editing = false
            end
        end
        if hide then
           _M.writeBotLeft(string.rep('+',#editVal))
        else
           _M.writeBotLeft(editVal..' ')
        end
    end
    _M.abortDialog()
    _M.restoreBot()

    return tonumber(editVal), ok
end

_M.REG_EDIT_REG = 0x0320
-------------------------------------------------------------------------------
--  Called to edit value of specified register
-- @param reg is the address of the register to edit
-- @param prompt is true if name of register to be displayed during editing,
-- or set to a literal prompt to display
-- @return value of reg
function _M.editReg(reg,prompt)
   endDisplayMessage()
   if (prompt) then
      _M.saveBot()
      if type(prompt) == 'string' then
         _M.writeBotRight(prompt)
      else
         _M.writeBotRight(_M.sendRegWait(_M.CMD_RDNAME,reg))
      end
   end
   _M.sendRegWait(_M.CMD_WRFINALDEC,_M.REG_EDIT_REG,reg)
   _M.startDialog()
   while true do
     local data,err = _M.sendRegWait(_M.CMD_RDFINALHEX,_M.REG_EDIT_REG)

     if err or (data and tonumber(data,16) ~= reg) then
       break
     end
     _M.delay(0.050)
     if not _M.dialogRunning() or not _M.app.running then
        _M.sendKey(_M.KEY_CANCEL,'long')
     end
   end
   _M.abortDialog()
   if prompt then
      _M.restoreBot()
   end
   return _M.literalToFloat(_M.sendRegWait(_M.CMD_RDLIT,reg))
end

-------------------------------------------------------------------------------
-- Called to delay for t sec while keeping event handlers running
-- @param t delay time in sec
function _M.delay(t)
    local delayWaiting = true
    local tmr = _M.system.timers.addTimer(0, t, function () delayWaiting = false end)
    while delayWaiting do
        _M.system.handleEvents()
    end
end

local askOKWaiting = false
local askOKResult = 0
-------------------------------------------------------------------------------
-- Private function
local function askOKCallback(key, state)

    if state ~= 'short' then
        return false
    end

    if key == _M.KEY_OK then
        askOKWaiting = false
        askOKResult = _M.KEY_OK
    elseif key == _M.KEY_CANCEL then
        askOKWaiting = false
        askOKResult = _M.KEY_CANCEL
    end

    return true
end

-------------------------------------------------------------------------------
-- Prompts operator and waits for OK or CANCEL key press
-- @param prompt string to put on bottom right LCD
-- @param q string to put on bottom left LCD
-- @param units optional units to display
-- @param unitsOther optional other units to display
-- @return either KEY_OK or KEY_CANCEL
function _M.askOK(prompt, q, units, unitsOther)

    local f = _M.keyGroup.keypad.callback
    local prompt = prompt or ''
    local q = q or ''
    local u = units or 0
    local uo = unitsOther or 0

    _M.setKeyGroupCallback(_M.keyGroup.keypad, askOKCallback)
    endDisplayMessage()
    _M.saveBot()
    _M.writeBotRight(prompt)
    _M.writeBotLeft(q)
    _M.writeBotUnits(0,0)
    _M.writeBotUnits(u,uo)

    askOKWaiting = true
    askOKResult = _M.KEY_CANCEL
   _M.startDialog()
    while _M.dialogRunning() and askOKWaiting and _M.app.running do
        _M.system.handleEvents()
    end
    _M.abortDialog()
    _M.setKeyGroupCallback(_M.keyGroup.keypad, f)

    _M.restoreBot()
    return askOKResult

end

-------------------------------------------------------------------------------
-- Prompts operator to select from a list of options using
-- arrow keys and KEY_OK
-- @param prompt string to put on bottom right LCD
-- @param options table of option strings
-- @param def default selection string.byte
-- @param loop If true, top option loops to the bottom option and vice versa
-- @param units optional units to display
-- @param unitsOther optional other units to display
-- @return selected string  if OK pressed or nil if CANCEL pressed
function _M.selectOption(prompt, options, def, loop,units,unitsOther)
    loop = loop or false
    local options = options or {'cancel'}
    local u = units or 0
    local uo = unitsOther or 0
    local key = 0
    local sel = nil

    local index = 1
    if def then
        for k,v in ipairs(options) do
            if v == def then
                index = k
            end
        end
    end

    editing = true
    endDisplayMessage()
    _M.saveBot()
    _M.writeBotRight(string.upper(prompt))
    _M.writeBotLeft(string.upper(options[index]))
    _M.writeBotUnits(u,uo)

   _M.startDialog()
    while editing and _M.app.running do
        key = _M.getKey(_M.keyGroup.keypad)
        if not _M.dialogRunning() then    -- editing aborted so return default
           editing = false
        elseif key == _M.KEY_DOWN then
            index = index + 1
            if index > #options then
              if loop then
                 index = 1
               else
                  index = #options
               end
            end
        elseif key == _M.KEY_UP then
            index = index - 1
            if index <= 0 then
               if loop then
                   index = #options
               else
                  index = 1
               end
            end
        elseif key == _M.KEY_OK then
            sel = options[index]
            editing = false
        elseif key == _M.KEY_CANCEL then
          editing = false
      end
      _M.writeBotLeft(string.upper(options[index]))

    end
    _M.abortDialog()

    _M.restoreBot()

    return sel
end

end

