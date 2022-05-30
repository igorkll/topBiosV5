local component, computer, unicode, table, bootfiles, nullfunc, debug_traceback = component, computer, unicode, table, {"/init.lua", "/OS.lua"}, function() end, debug.traceback
local unicode_sub, unicode_len, unicode_char = unicode.sub, unicode.len, unicode.char
local component_list, component_invoke, component_proxy = component.list, component.invoke, component.proxy
local computer_pullSignal, computer_shutdown, computer_uptime = computer.pullSignal, computer.shutdown, computer.uptime
local table_insert, table_concat, table_remove, table_sort, table_unpack = table.insert, table.concat, table.remove, table.sort, table.unpack

--------------------------------------------components

local function getBestGPUOrScreenAddress(componentType) --функцию подарил игорь тимофеев
    local bestAddress, bestWidth, width

    for address in component_list(componentType) do
        width = tonumber(device[address].width)

        if not bestWidth or width > bestWidth then
            bestAddress, bestWidth = address, width
        end
    end

    return bestAddress
end

function getCP(ctype)
    return component_proxy(component_list(ctype)())
end

--[[
function getCP(ctype)
    local maxlevel, deviceaddress, finded = 0

    while 1 do
        finded = nil
        for address, ltype in component_list(ctype) do
            if ctype == ltype then
                local level = tonumber(device[address].width) or nil
                if not level then
                    deviceaddress = address
                elseif level > maxlevel then
                    maxlevel = level
                    deviceaddress = address
                    finded = 1
                    break
                end
            end
        end
        if not finded then
            local address = component_proxy(deviceaddress or "")
            return address
        end
    end
end
]]

local eeprom = component_list("eeprom")()

function resetPalette()
    local colors
    if depth == 8 then
        colors = 
        {0x000000, 0x111111, 0x222222, 0x333333,
        0x444444, 0x555555, 0x666666, 0x777777,
        0x888888, 0x999999, 0xAAAAAA, 0xBBBBBB,
        0xCCCCCC, 0xDDDDDD, 0xEEEEEE, 0xFFFFFF}
    elseif depth == 4 then
        colors = 
        {0xFFFFFF, 0xF2B233, 0xE57FD8, 0x99B2F2,
        0xFEFE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
        0x999999, 0x4C99B2, 0xB266E5, 0x3333FF,
        0x9F664C, 0x57A64E, 0xFF3333, 0x000000}
    end
    if colors then
        for i, v in ipairs(colors) do
            gpu.setPaletteColor(i - 1, v)
        end
    end
end

--------------------------------------------functions

function split(str, sep)
    local parts, count, i = {}, 1, 1
    while 1 do
        if i > #str then break end
        local char = str:sub(i, #sep + (i - 1))
        if not parts[count] then parts[count] = "" end
        if char == sep then
            count = count + 1
            i = i + #sep
        else
            parts[count] = parts[count] .. str:sub(i, i)
            i = i + 1
        end
    end
    if str:sub(#str - (#sep - 1), #str) == sep then table_insert(parts, "") end
    return parts
end
_G.split = split

function getDataPart(part)
    return split(eeprom_getData(), "\n")[part] or ""
end

function setDataPart(part, newdata)
    if getDataPart(part) == newdata then return end
    if newdata:find("\n") then error("\\n char") end
    local parts = split(eeprom_getData(), "\n")
    for i = part, 1, -1 do
        if not parts[i] then parts[i] = "" end
    end
    parts[part] = newdata
    eeprom_setData(table_concat(parts, "\n"))
end

function delay(time, func)
    if not func then func = function() computer_pullSignal(0.1) end end
    local inTime = computer_uptime()
    while computer_uptime() - inTime < time do
        if func() == false then
            break
        end
    end
end

function getLabel(address, file)
    local label = component_invoke(address, "getLabel")
    return ((label and (label .. ":")) or "") .. address:sub(1, 3) .. ":" .. file
end

function labelIsReadonly(proxy)
    return not pcall(proxy.setLabel, proxy.getLabel())
end

function formatString(str, size, mode)
    local str1 = " "

    str = unicode_sub(str, 1, size)
    local value, substr = size - unicode_len(str), str1:rep(size - unicode_len(str))

    if mode == 1 then
        return substr .. str
    elseif mode == 2 then
        str = str1:rep(value // 2) .. str .. str1:rep(value // 2)
        if #str < size then
            str = str .. str1:rep(size - unicode_len(str))
        end
        return str
    else
        return str .. substr
    end
end

function getError(err)
    return err or "Unknown Error"
end

function toValue(value)
    if type(value) == "function" then
        return value()
    else
        return value
    end
end

function fsList()
    local tbl = {}

    for address in component_list("filesystem") do
        table_insert(tbl, address)
    end

    table_sort(tbl, function(str1, str2)
        for i = 1, #str1 do
            if str1:sub(i, i) ~= str2:sub(i, i) then
                return str1:byte(i) < str2:byte(i)
            end
        end
    end)

    return ipairs(tbl)
end

function boots(address)
    local function preBoots(address)
        local proxy = component_proxy(address)
        if not proxy then return {} end

        local buffer, addresses = {}, {}

        for i, v in ipairs(bootfiles) do
            if proxy.exists(v) then
                table_insert(buffer, v)
                table_insert(addresses, address)
            end
        end

        local path = "/boot/kernel/"
        for _, file in ipairs(proxy.list(path) or {}) do
            table_insert(buffer, path .. file)
            table_insert(addresses, address)
        end

        return buffer, buffer, addresses
    end
    if address then
        return preBoots(address)
    else
        local buffer, files, addresses = {}, {}, {}
        for _, address in fsList() do
            local label = component_invoke(address, "getLabel")
            local tbl = preBoots(address)
            for i, v in ipairs(tbl) do
                table_insert(buffer, (label and (label .. "-") or "") .. address:sub(1, 3) .. "-" .. v)
                table_insert(files, v)
                table_insert(addresses, address)
            end
        end
        return buffer, files, addresses
    end
end

function getLabel2(proxy)
    return proxy.getLabel() or "Unnamed"
end

function fsName(address)  --взято из mineOS efi от игорь тимофеев
    local proxy = component_proxy(address)
    return formatString(getLabel2(proxy), 12) .. "  " .. (proxy.spaceTotal() >= 1048576 and "HDD" or proxy.spaceTotal() >= 65536 and "FDD" or "SYS") .. "  " .. (proxy.isReadOnly() and "R  " or "R/W") .. "  " .. formatString(string.format("%.1f", proxy.spaceUsed() / proxy.spaceTotal() * 100) .. "%", 6, 1) .. "  " .. formatString(address, 7) .. "…"
end

--------------------------------------------graphic init

gpu = component_proxy(getBestGPUOrScreenAddress("gpu") or "*")
if gpu then
    screen = getDataPart(2)
    if not component_proxy(screen) then
        screen = getBestGPUOrScreenAddress("screen")
        if screen then
            setDataPart(2, screen)
        end
    end
    if screen then
        keyboard = component_invoke(screen, "getKeyboards")[1]
        gpu.bind(screen)
    end
end
if screen then
    rx, ry = gpu.getResolution()
    mx, my = gpu.maxResolution()
    maxDepth = math.floor(gpu.maxDepth())
    depth = math.floor(gpu.getDepth())
    pcall(component_invoke, screen, "setPrecise", false)
end
if not gpu or not screen then
    gpu = nil
    screen = nil
end
--------------------------------------------functions

isControl = screen and (keyboard or (math.floor(device[screen].width) ~= 1))

--------------------------------------------graphic

function setResolution(rx2, ry2, depth2)
    gpu.setResolution(rx2 or rx, ry2 or ry)
    gpu.setDepth(depth2 or depth)
    depth = gpu.getDepth()
    rx, ry = gpu.getResolution()
    setDataPart(5, tostring(rx))
    setDataPart(6, tostring(ry))
    setDataPart(7, tostring(depth))
    resetPalette()
end

if screen then
    local x, y, d = getDataPart(5), getDataPart(6), getDataPart(7)
    if x == "" then x = rx end
    if y == "" then y = ry end
    if d == "" then d = depth end
    x = tonumber(x)
    y = tonumber(y)
    d = tonumber(d)
    if y > my or x > mx or d > maxDepth then
        x = mx
        y = my
        d = maxDepth
    end
    setResolution(x, y, d)
end

function selectColor(mainColor, simpleColor, bw)
    if depth == 4 then
        return simpleColor or mainColor
    elseif depth == 1 then
        return bw and 0xFFFFFF or 0
    else
        return mainColor
    end
end

local mainback, mainfore
local function refreshMain()
    mainback, mainfore = selectColor(0xE1E1E1, 0xFFFFFF, true), selectColor(0x878787, 0x4C4C4C, false)
end
refreshMain()

local statusBack, statusFore
local menuBack, menuFore, menuLogoBack, menuLogoFore
local inputBack, inputFore

local themes = {{name = "Classic", minDepth = 1}, {name = "White", minDepth = 1}, {name = "Black", minDepth = 1}, {name = "Cyan", minDepth = 4}, {name = "Red", minDepth = 8}, {name = "matrix", minDepth = math.huge}}
local theme
local themeAnimated
local themeAnimationTime
function setTheme(num, splash)
    if not themes[num] or depth < themes[num].minDepth then return false end
    themeAnimated = false
    themeAnimationTime = nil
    if num == 1 then --classic
        statusBack, statusFore = mainback, mainfore
        inputBack, inputFore = mainback, mainfore
        menuBack, menuFore, menuLogoBack, menuLogoFore = mainback, mainfore, selectColor(mainback, nil, false), selectColor(0, nil, true)
    elseif num == 2 then --white
        statusBack, statusFore = 0xFFFFFF, 0
        inputBack, inputFore = 0xFFFFFF, 0
        menuBack, menuFore, menuLogoBack, menuLogoFore = 0xFFFFFF, 0, 0, 0xFFFFFF
    elseif num == 3 then --black
        statusBack, statusFore = 0, 0xFFFFFF
        inputBack, inputFore = 0, 0xFFFFFF
        menuBack, menuFore, menuLogoBack, menuLogoFore = 0, 0xFFFFFF, 0xFFFFFF, 0
    elseif num == 4 then --cyan
        statusBack, statusFore = selectColor(0x002b36, 0x3333FF), selectColor(0x8cb9c5, 0x4C99B2)
        inputBack, inputFore = statusBack, statusFore
        menuBack, menuFore, menuLogoBack, menuLogoFore = statusBack, statusFore, statusBack, 0xFFFFFF
    elseif num == 5 then --red
        statusBack, statusFore = 0x880000, 0xFF0000
        inputBack, inputFore = statusBack, statusFore
        menuBack, menuFore, menuLogoBack, menuLogoFore = statusBack, statusFore, 0xFF5500, 0xFFAA00
    elseif num == 6 then
        statusBack, statusFore = 0x000000, 0x00FF00
        inputBack, inputFore = statusBack, statusFore
        menuBack, menuFore, menuLogoBack, menuLogoFore = statusBack, statusFore, statusFore, statusBack
        themeAnimated = true
        themeAnimationTime = 0.2
    end
    theme = num
    if status and splash then
        status("installed the theme: " .. themes[num].name)
    end
    setDataPart(8, tostring(num))
    return true
end

function checkTheme()
    local th = getDataPart(8)
    th = tonumber(th)
    if not th then th = 1 end
    refreshMain()
    if not setTheme(th) then
        setTheme(1)
    end
end

if screen then
    checkTheme()
end

function setColor(back, fore)
    gpu.setBackground(back or mainback)
    gpu.setForeground(fore or mainfore)
end

function clear(back, fore)
    setColor(back, fore)
    gpu.fill(1, 1, rx, ry, " ")

    if theme == 6 then
        for i = 1, 100 do
            gpu.set(math.random(1, rx), math.random(1, ry), string.char(math.random(32, 127)))
        end
    end
end

function invert()
    gpu.setForeground(gpu.setBackground(gpu.getForeground()))
end

function setText(text, posY)
    local posX = ((rx // 2) - (unicode_len(text) // 2)) + 1
    gpu.set(posX, posY, text)
    return posX
end

function status(text, del, err)
    if not screen then
        if err then
            error(text, 0)
        end
        return
    end
    if not isControl and del == true then del = 1 end
    clear(statusBack, statusFore)
    setText(text, ry // 2)
    if del == true then
        setText("Press Enter Or Touch To Continue", (ry // 2) + 1)
        while true do
            local eventName, uuid, _, code, button = computer_pullSignal(themeAnimationTime)
            if eventName == "touch" and button == 0 and uuid == screen then
                break
            elseif eventName == "key_down" and code == 28 and uuid == keyboard then
                break
            end
        end
    else
        if del then
            if del < 0 then return end
            delay(math.max(del, 0.5))
        else
            delay(0.5)
        end
    end
end

function menu(label, inStrs, num)
    if not num or num < 1 then num = 1 end
    if num > #inStrs then num = #inStrs end

    local max = 0
    for i, v in ipairs(inStrs) do
        if unicode_len(v) > max then
            max = unicode_len(v)
        end
    end

    local strs = {}
    table_insert(strs, "")
    for i, v in ipairs(inStrs) do
        table_insert(strs, formatString(v, max + 4, 2))
    end

    local pos, posY, oldpos, poss = (num or 1) + 1, (ry // 2) - (#strs // 2), nil, {}
    if posY < 1 then posY = 1 end
    while 1 do
        local startpos = (pos // ry) * ry

        if pos ~= oldpos then
            clear(menuBack, menuFore)
            if startpos == 0 then
                setColor(menuLogoBack, menuLogoFore)
                setText(label, posY)
            end
            setColor(menuBack, menuFore)
            for i = 1, #strs do
                local drawpos = (posY + i) - startpos
                if drawpos >= 1 then
                    if drawpos > ry then break end
                    if i == pos then invert() end
                    poss[i] = setText(strs[i], drawpos)
                    if i == pos then invert() end
                end
            end
        end

        local eventData = {computer_pullSignal(themeAnimationTime)}
        oldpos = pos
        if #eventData > 0 then
            if eventData[1] == "key_down" and eventData[2] == keyboard then
                if eventData[4] == 28 then
                    break
                elseif eventData[4] == 200 then
                    pos = pos - 1
                elseif eventData[4] == 208 then
                    pos = pos + 1
                end
            elseif eventData[1] == "scroll" and eventData[2] == screen then
                pos = pos - eventData[5]
            elseif eventData[1] == "touch" and eventData[2] == screen and eventData[5] == 0 then
                local ty = (eventData[4] - posY) + startpos
                if ty >= 2 and ty <= #strs and eventData[3] >= poss[ty] and eventData[3] < (poss[ty] + unicode_len(strs[ty])) then
                    pos = ty
                    break
                end
            end
            if pos < 2 then pos = 2 end
            if pos > #strs then pos = #strs end
        end
        if themeAnimated then
            oldpos = -1
        end
    end
    return pos - 1
end

function menuPro(label, strs, utilities, noBack, refreshMode, num, autoback)
    if num and num > #strs then num = 1 end
    while 1 do
        local strs2 = {}
        for i, v in ipairs(strs) do
            table_insert(strs2, toValue(v))
        end

        if not noBack then
            table_insert(strs2, "Back")
        end
        num = menu(toValue(label), strs2, num)
        if not noBack then
            table_remove(strs2, #strs2)
        end

        if utilities[num] then
            local ok, err = pcall(utilities[num])
            nullfunc()
            if not ok then
                status(getError(err), true)
            end
            if autoback then
                return nil
            end
            if refreshMode then
                return num
            end
            if ok and err == "back" then
                return nil
            end
        else
            break
        end
    end
end

local inputBuf = {}
function input(text, crypto)
    local buffer, center, select = "", ry // 2, 0

    local function redraw()
        clear(inputBack, inputFore)
        local buffer = buffer
        if crypto then
            local str1 = "*"
            buffer = str1:rep(unicode_len(buffer))
        end

        local drawtext = text .. ": " .. buffer .. "_"
        setText(drawtext, center)
    end

    while 1 do
        redraw()
        local eventName, uuid, char, code = computer_pullSignal(themeAnimationTime)
        if eventName then
            if eventName == "key_down" and uuid == keyboard then
                if code == 28 then
                    if #buffer > 0 then
                        if not crypto and buffer ~= inputBuf[1] and buffer ~= "" then
                            table_insert(inputBuf, 1, buffer)
                        end
                        return buffer
                    end
                elseif code == 200 or code == 208 then
                    buffer = ""
                    if code == 200 then
                        if select < #inputBuf then
                            select = select + 1
                        end
                    else
                        if select > 0 then
                            select = select - 1
                        end
                    end
                    buffer = inputBuf[select] or ""
                    redraw()
                elseif code == 14 then
                    if unicode_len(buffer) > 0 then
                        select = 0
                        buffer = unicode_sub(buffer, 1, unicode_len(buffer) - 1)
                        redraw()
                    end
                elseif char == 3 then
                    return nil
                elseif char >= 32 and char <= 127 then
                    select = 0
                    buffer = buffer .. unicode_char(char)
                    redraw()
                end
            elseif eventName == "clipboard" and uuid == keyboard then
                select = 0
                buffer = buffer .. char
                if unicode_sub(char, unicode_len(char), unicode_len(char)) == "\n" then
                    local data = unicode_sub(buffer, 1, unicode_len(buffer) - 1)
                    if not crypto and inputBuf[1] ~= data and inputBuf[1] ~= "" then
                        table_insert(inputBuf, 1, data)
                    end
                    return data
                end
            elseif eventName == "touch" and uuid == screen then
                if #buffer == 0 then
                    return nil
                end
            end
        end
    end
end

function yesno(label, simple, back)
    if back then
        local out = menu(label, {"No", "Yes", "Back"})
        if out == 3 then
            return nil
        else
            return out == 2
        end
    else
        if simple then
            return menu(label, {"No", "Yes"}) == 2
        else
            return menu(label, {"No", "No", "Yes", "No"}) == 3
        end
    end
end

--------------------------------------------boot

function isBoot(address, file)
    local ok, out = pcall(component_invoke, address, "exists", file)
    return ok and out and not component_invoke(address, "isDirectory", file)
end

function bootTo(bootaddress, bootfile)
    status("Boot From: " .. getLabel(bootaddress, bootfile), 1)

    local bootcode = getFile(component_proxy(bootaddress), bootfile)

    function computer.getBootAddress()
        return bootaddress
    end
    function computer.getBootScreen()
        return screen
    end
    function computer.getBootGpu()
        if screen then
            return gpu.address
        end
        return nil
    end
    function computer.getBootFile()
        return bootfile
    end

    function computer.setBootAddress(address)
        setDataPart(1, address or "")
        if address == "" then
            setDataPart(3, "")
            return
        end

        local setFile
        for i, v in ipairs(bootfiles) do
            if component_invoke(address, "exists", v) then
                setDataPart(3, v)
                setFile = 1
                break
            end
        end

        if not setFile then
            setDataPart(3, "")
        end
    end
    function computer.setBootScreen(address)
        setDataPart(2, address or "")
    end
    function computer.setBootFile(file)
        setDataPart(3, file or "")
    end

    function computer.shutdown(state)
        if state == "fast" then
            setDataPart(4, bootaddress .. ";" .. bootfile)
            computer_shutdown(1)
        else
            computer_shutdown(state)
        end
    end

    if bootfile == "/OS.lua" then
        component_proxy(eeprom).getData = function() --для запуска mineOS, подменяю proxy а не invoke, потому что это менее громостко а изменения сами откатяться при сборки мусора
            return bootaddress
        end
    end

    computer.beep(1000, 0.2)
    local ok, err = xpcall(assert(load(bootcode, "=init")), debug_traceback)
    if not ok then
        nullfunc = function()
            error(err, 0)
        end
        nullfunc()
    end
    computer_shutdown()
end

--------------------------------------------menu

function executeString(str, forceStatus)
    local code, err = load(str)
    if not code then
        status(getError(err), true)
        return nil, err
    end
    local dat = {pcall(code)}
    if not dat[1] then
        status(getError(tostring(dat[2])), true)
    end
    if forceStatus and dat[1] and dat[2] then
        status(getError(tostring(dat[2])), true)
    end
    return table_unpack(dat)
end

function checkPassword(skip)
    local password = getDataPart(9)
    while password ~= "" do
        if not screen then
            if skip then
                return false
            else
                computer_shutdown()
            end
        end
        local read = input("Password", true)
        if not read then
            if skip then
                return false
            else
                computer_shutdown()
            end
        end
        if read == password then
            return true
        else
            status("The Password Doesn't Fit", 1)
        end
    end
    return true
end
if getDataPart(11) == "" then
    checkPassword()
end

--proxy.spaceTotal() >= 1048576 and "HDD" or proxy.spaceTotal() >= 65536 and "FDD" or "SYS"
--…
local function diskMenager()
    local strs, utilities = {}, {}
    for _, address in fsList() do
        local proxy, num = component_proxy(address), nil

        local function generateLabel()
            return (getDataPart(1) == address and "> " or "  ") .. fsName(address) .. "  "
        end
        table_insert(strs, generateLabel)
    
        table_insert(utilities, function()
            ::refresh::
            local strs = {}
            local utilities = {}

            local kernelTbl = proxy.list("/boot/kernel") or {}
            if proxy.exists("/init.lua") or proxy.exists("/OS.lua") or #kernelTbl > 0 then
                table_insert(strs, "Set As Bootable")
                table_insert(strs, "Fastboot")

                for i = 1, 2 do
                    table_insert(utilities, function()
                        local strs = {}
                        local utilities = {}

                        local function addFile(file)
                            table_insert(utilities, function()
                                if i == 1 then
                                    status("Seting As Bootable")
                                    setDataPart(1, proxy.address)
                                    setDataPart(3, file)
                                else
                                    bootTo(proxy.address, file)
                                end
                            end)
                        end

                        if i == 1 then
                            table_insert(strs, "Any")
                            addFile("any")
                        end

                        for i, v in ipairs(bootfiles) do
                            if proxy.exists(v) then
                                table_insert(strs, v)
                                addFile(strs[#strs])
                            end
                        end

                        for _, file in ipairs(kernelTbl) do
                            table_insert(strs, "/boot/kernel/" .. file)
                            addFile(strs[#strs])
                        end

                        menuPro("Select Boot File", strs, utilities, nil, nil, nil, true)
                    end)
                end
            end

            if not labelIsReadonly(proxy) then
                if keyboard then
                    table_insert(strs, "Change Label")
                    table_insert(utilities, function()
                        local read = input("Label")
                        if read then
                            proxy.setLabel(read)
                        end
                    end)
                end

                table_insert(strs, "Erase Label")
                table_insert(utilities, function()
                    proxy.setLabel(nil)
                end)
            end

            local fromAddress = address
            local installCount = 0
            for _, address in fsList() do
                local toProxy = component_proxy(address)
                if not toProxy.isReadOnly() and address ~= fromAddress and toProxy.spaceTotal() >= proxy.spaceUsed() then
                    installCount = installCount + 1
                end
            end
            if installCount > 0 then
                table_insert(strs, "Move Data")
                table_insert(utilities, function()
                    local function fsTag(address)
                        local label = component_proxy(address).getLabel()
                        if label == "" then
                            label = nil
                        end
                        return (label and (label .. "-") or "") .. address:sub(1, 3)
                    end

                    local strs = {}
                    local utilities = {}
                    for _, address in fsList() do
                        local toProxy = component_proxy(address)
                        if not toProxy.isReadOnly() and address ~= fromAddress and toProxy.spaceTotal() >= proxy.spaceUsed() then
                            local function generateLabel()
                                return fsName(address)
                            end

                            table_insert(strs, generateLabel)
                            table_insert(utilities, function()
                                local format = yesno("Format Target Drive?", nil, 1)
                                if format == nil then return end
                                if menu("From: " .. fsTag(fromAddress) .. ", To: " .. fsTag(address) .. ", Format: " .. tostring(format), {"Confirm", "Cancel"}) == 1 then
                                    if format then
                                        status("formating")
                                        for _, file in ipairs(toProxy.list("/")) do
                                            if file ~= ".efi" and file ~= ".efiData" then
                                                toProxy.remove(file)
                                            end
                                        end
                                    end
                                    local function install(from, to, path)
                                        for _, file in ipairs(from.list(path)) do
                                            local full_path = path .. file
                                            if from.isDirectory(full_path) then
                                                to.makeDirectory(full_path)
                                                install(from, to, full_path)
                                            elseif full_path ~= ".efi" and full_path ~= "/.efi" and full_path ~= ".efiData" and full_path ~= "/.efiData" then
                                                local data = getFile(from, full_path)
                                                local file = to.open(full_path, "wb")
                                                to.write(file, data)
                                                to.close(file)
                                            end
                                        end
                                    end
                                    status("Moving Files")
                                    install(proxy, toProxy, "/")
                                    return "back"
                                end
                            end)
                        end
                    end
                    menuPro("Select Target Drive, To Clone: " .. fsTag(fromAddress), strs, utilities)
                end)
            end

            if not proxy.isReadOnly() then
                table_insert(strs, "Format")
                table_insert(utilities, function()
                    if yesno("Format?") then
                        status("formating")
                        for _, file in ipairs(proxy.list("/")) do
                            if file ~= ".efi" and file ~= ".efiData" then
                                proxy.remove(file)
                            end
                        end
                        if address == getDataPart(1) then
                            setDataPart(1, "")
                            setDataPart(3, "")
                        end
                    end
                end)
            end

            num = menuPro(function() return (proxy.getLabel() or "Unnamed") .. " (" .. address .. ")" end, strs, utilities, nil, 1, num)
            if num then
                goto refresh
            end
        end)
    end
    menuPro("Disk Menager", strs, utilities)
end

function internetBoot(url)
    url = url or input("Url")
    if not url then return end
    return executeString(assert(getInternetFile(url)))
end

local function internetApp()
    while true do
        local url = input("Url")
        if not url then return end
        local data, err = getInternetFile(url)
        if not data then
            status(getError(err), true)
        else
            return executeString(data)
        end
    end
end

local function runWebUtility()
    local dat, utility, strs = assert(getInternetFile("https://raw.githubusercontent.com/igorkll/webMarket3/main/list.txt")), {}, {}
    local datas = split(dat, "\n")

    for i, v in ipairs(datas) do
        local subdat = split(v, ";")
        
        table_insert(strs, subdat[2])
        table_insert(utility, function()
            internetBoot(subdat[1])
        end)
    end

    menuPro("Select Os To Install", strs, utility)
end

local function lua()
    while 1 do
        local read = input("Lua Code")
        if not read then break end
        if read == "reset" then
            --[[
            status("Resetting")
            eeprom_setData("")
            computer_shutdown(1)
        elseif read == "clearboot" then
            status("Clearing")
            setDataPart(1, "")
            setDataPart(3, "")]]
        else
            executeString(read, 1)
        end
    end
end

local function usersManager()
    local num
    while true do
        local strs = {}
        for _, user in ipairs{computer.users()} do
            table_insert(strs, user)
        end
        if keyboard then
            table_insert(strs, "Add User")
        end
        table_insert(strs, "Remove All(Set A Public)")
        table_insert(strs, "Back")

        num = menu("Users Manager, Public: " .. tostring(#{computer.users()} == 0), strs, num)

        if num == #strs then
            break
        elseif num == (#strs - 1) then
            if yesno("Remove All Users? The Computer Will Become Public") then
                for _, user in ipairs{computer.users()} do
                    computer.removeUser(user)
                end
            end
        elseif num == (#strs - 2) and keyboard then
            local read = input("Nikname")
            if read then
                local ok, err = computer.addUser(read)
                if not ok then
                    status(getError(err), true)
                end
            end
        else
            local user = strs[num]

            local num
            while true do
                num = menu("Control User: " .. user, {"Remove", "Back"}, num)
                if num == 1 then
                    if yesno("Remove User " .. user .. "?") then
                        computer.removeUser(user)
                        break
                    end
                elseif num == 2 then
                    break
                end
            end
        end
    end
end

local function checkAdminPassword(skip)
    local password = getDataPart(10)
    if password == "" then password = "0000" end

    while true do
        local read = input("Enter Admin Password", true)
        if not read then
            if skip then
                return false
            else
                computer_shutdown()
            end
        end
        if read == password then
            return true
        else
            status("The Password Doesn't Fit", 1)
        end
    end
end

local function password()
    local function setPassword(admin)
        local function check(str)
            if not str then return true end
            if unicode_len(str) < 4 then
                status("The Password Must Be Longer Than Four Characters", true)
                return true
            end
        end
        local read1 = input("Enter New " .. (admin and "Admin " or "") .. "Password", true)
        if check(read1) then return end
        local read2 = input("Commit New " .. (admin and "Admin " or "") .. "Password", true)

        if read1 == read2 then
            status("the password is set", 0.5)
            if admin then
                setDataPart(10, read1)
            else
                setDataPart(9, read1)
            end
        else
            status("passwords don't match", 0.5)
        end
    end
    local function clearPassword()
        if yesno("Clear Password?") then
            setDataPart(9, "")
        end
    end
    if not checkAdminPassword(true) then
        return
    end

    menuPro("Password", {"Set Admin Password", "Set Password", "Clear Password", function()
        if getDataPart(11) == "1" then
            return "Mode:mainmenu"
        else
            return "Mode:boot"
        end
    end}, {function()
        setPassword(true)
    end, setPassword, clearPassword, function()
        local num = getDataPart(11) == "1" and 2 or 1
        num = menu("Select Mode", {"Boot", "Main Menu"}, num)
        if num == 1 then
            setDataPart(11, "")
        elseif num == 2 then
            setDataPart(11, "1")
        end
    end})
end

local function themesUtiles()
    local num = tonumber(getDataPart(8))
    while true do
        local strs = {}
        local lThemes = {}

        for i = 1, #themes do
            if depth >= themes[i].minDepth then
                table_insert(strs, themes[i].name)
                table_insert(lThemes, i)
            end
        end
        table_insert(strs, "Back")

        num = menu("Select Theme", strs, num)
        local theme = lThemes[num]
        if not theme then
            break
        end
        setTheme(theme, true)
    end
end

local function resolutions()
    local function isValide(x, y)
        return not (y > mx or ((x * y) > (mx * my)))
    end
    local function check(x, y, noStatus)
        if not isValide(x, y) then
            if not noStatus then
                status("unsupported resolution", true)
            end
            return false
        end
        if x < 16 or y < 4 then
            if not noStatus then
                status("the resolution is too small", true)
            end
            return false
        end
        return true
    end

    local resolutions = {{160, 50}, {80, 25}, {50, 16}, {80, 40}, {40, 20}}
    if keyboard then
        table_insert(resolutions, "custom")
    end

    local strs = {}
    local funcs = {}
    for i, v in ipairs(resolutions) do
        local str = type(v) == "string" and v or table_concat(v, ":")
        local cx, cy
        if type(v) == "table" then
            cx, cy = table_unpack(v)
        end

        if not cx or isValide(cx, cy) then
            table_insert(strs, str)
            table_insert(funcs, function()
                local lx, ly
                if type(v) == "table" then
                    lx, ly = table_unpack(v)
                else
                    local input = input("resolution(x y)")
                    if input then
                        local tbl = split(input, " ")
                        local sx, sy = tonumber(tbl[1]), tonumber(tbl[2])
                        if type(sx) ~= "number" then sx = nil end
                        if type(sy) ~= "number" then sy = nil end
                        if not sx or not sy or sx <= 0 or sy <= 0 then
                            status("input error", true)
                            return
                        end
                        lx, ly = sx, sy
                    end
                end
                if lx and check(lx, ly) then
                    setResolution(lx, ly, depth)
                end
            end)
        end
    end

    local num
    for i = 1, #resolutions - 1 do
        if resolutions[i][1] == math.floor(rx) and resolutions[i][2] == math.floor(ry) then
            num = i
            break
        end
    end
    if not num then
        num = #resolutions
    end

    menuPro("Resolution", strs, funcs, nil, nil, num)
end

local function depths()
    local num
    local findFlag = true
    while true do
        local strs = {}
        local lDepths = {}

        local depthsName = {"8 Bits", "4 Bits", "1 Bit"}
        local depths = {8, 4, 1}

        for i = 1, #depths do
            if depths[i] <= maxDepth then
                table_insert(strs, depthsName[i])
                table_insert(lDepths, depths[i])
            end
        end

        if findFlag then
            findFlag = false

            local current = math.floor(tonumber(getDataPart(7)))
            for i = 1, #lDepths do
                if lDepths[i] == current then
                    num = i
                    break
                end
            end
        end

        table_insert(strs, "Back")

        num = menu("Select Depth", strs, num)
        local depth = lDepths[num]
        if not depth then
            break
        end
        setResolution(rx, ry, depth)
        checkTheme()
    end
end

local function options()
    local modes = {function()
        return "  Enable Multi Booting" .. (getDataPart(1) == "any" and " √" or "  ")
    end, "Reset Settings", "Users Manager", "Color Depth", "Resolution", "Themes"}
    local utilities = {function()
        status("Enabling Multi Booting")
        setDataPart(1, "any")
    end, function()
        if checkAdminPassword(true) and yesno("Reset EFI Settings?") then
            eeprom_setData("")
            computer.shutdown(true)
        end
    end, usersManager, depths, resolutions, themesUtiles}

    if keyboard then
        table_insert(modes, 6, "Password")
        table_insert(utilities, 6, password)
    end

    menuPro("Settings", modes, utilities)
end

local function internetApps()
    local modes, utilities = {},
    {}

    table_insert(modes, "Install Operating System")
    table_insert(utilities, runWebUtility)

    if keyboard then
        table_insert(modes, "Internet Boot")
        table_insert(utilities, internetApp)
    end

    menuPro("Internet", modes, utilities)
end

local function applications()
    local modes, utilities = {},
    {}

    if keyboard then
        table_insert(modes, "Lua Interpreter")
        table_insert(utilities, lua)
    end

    for address in component_list("filesystem") do
        local proxy = component_proxy(address)
        local path = "/smartEfi/applications/"
        for _, file in ipairs(proxy.list(path) or {}) do
            local full_path = path .. file
            if not proxy.isDirectory(full_path) then
                table_insert(modes, file)
                table_insert(utilities, function()
                    local file, err = getFile(proxy, full_path)
                    if not file then
                        status("error to get file: " .. getError(err), true)
                        return
                    end
                    local code, err = load(file)
                    if not code then
                        status("error to load programm:" .. getError(err), true)
                        return
                    end
                    local metaTbl = {driveAddress = address, path = full_path}
                    local ok, err = pcall(code, metaTbl)
                    if not ok then
                        status("error to running programm:" .. getError(err), true)
                        return
                    end
                end)
            end
        end
    end

    menuPro("Applications", modes, utilities)
end

--OpenOS 1.7.5 with the mod (recommended)
--OpenOS 1.7.5
--MineOS
local function biosmenu()
    if getDataPart(11) == "1" then
        if not checkPassword(true) then
            return true
        end
    end

    local modes, utilities = {"Disk Manager", "Applications", "Settings", "Shutdown", "Reboot"},
    {diskMenager, applications, options, computer_shutdown, function() computer_shutdown(1) end}

    if internet then
        table_insert(modes, 3, "Internet")
        table_insert(utilities, 3, internetApps)
    end

    menuPro("Smart EFI", modes, utilities)
end

--------------------------------------------main

::respring::

if isControl and getDataPart(4) == "" then
    ::tonew::
    if keyboard then
        status("Press Alt To Open The Efi Menu", -1)
    else
        status("Tap On The Screen To Open The Efi Menu", -1)
    end
    local toNew
    delay(1, function()
        local eventData = {computer_pullSignal(0.1)}
        if eventData[1] == "key_down" and eventData[2] == keyboard then
            if eventData[4] == 56 then
                toNew = biosmenu()
                if toNew then return false end
            elseif eventData[4] == 28 then
                return false
            end
        elseif eventData[1] == "touch" and eventData[2] == screen then
            if eventData[5] == 0 then
                toNew = biosmenu()
                if toNew then return false end
            else
                return false
            end
        end
    end)
    if toNew then
        goto tonew
    end
end

local mainbootaddress, mainbootfile = table_unpack(split(getDataPart(4), ";"))
local mainboot = getDataPart(4) ~= ""
setDataPart(4, "")

::revalue::
local bootaddress, bootfile = getDataPart(1), getDataPart(3)
local anyBoot, anyBoot2 = (bootfile == "any") and #boots(bootaddress) > 0, (bootaddress == "any") and #boots() > 0

if mainboot and isBoot(mainbootaddress, mainbootfile) then
    bootTo(mainbootaddress, mainbootfile)
elseif anyBoot or anyBoot2 then
    local bootsFiles, files, addresses
    if anyBoot2 then
        bootsFiles, files, addresses = boots()
    else
        bootsFiles, files, addresses = boots(bootaddress)
    end
    if isControl then
        local bootsfuncs = {}
        for i = 1, #bootsFiles do
            table_insert(bootsfuncs, function()
                bootTo(addresses[i], files[i])
            end)
        end

        menuPro("Select Boot File", bootsFiles, bootsfuncs)
    else
        bootTo(addresses[1], files[1])
    end
elseif not isBoot(bootaddress, bootfile) then
    status("Search For A Bootable Disk", 0.5)

    for _, address in fsList() do
        local proxy, setted = component_proxy(address)

        local function set(file)
            if proxy.exists(file) then
                status("Set As Bootable: " .. getLabel(address, file))
                setDataPart(1, address)
                setDataPart(3, file)
                setted = 1
                return 1
            end
        end

        if set("/boot/kernel/pipes") then
            break
        end

        if screen and set("/OS.lua") then
            break
        else
            if set("/init.lua") then
                break
            end
        end

        local path = "/boot/kernel/"
        for _, file in ipairs(proxy.list(path) or {}) do
            if set(path .. file) then
                break
            end
        end

        if setted then
            break
        end
    end

    if isBoot(getDataPart(1), getDataPart(3)) then
        goto revalue
    else
        status("No Bootable Medium Found", true, 1)
    end
else
    bootTo(bootaddress, bootfile)
end

goto respring