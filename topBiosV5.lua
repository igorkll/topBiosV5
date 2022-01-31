local function getComponent(type) return component.proxy(component.list(type)() or "") end
local eeprom = getComponent("eeprom")
local internet = getComponent("internet")

-------------------------------------------------------guard

local originalInvoke = component.invoke
computer.setArchitecture = nil
local error, xpcall, assert, shutdown, checkArg, pairs, type, unpack, traceback = error, xpcall, assert, computer.shutdown, checkArg, pairs, type, table.unpack, debug.traceback
local eepromFakeFunctions = {makeReadonly = false, get = "", set = {nil, "storage is readonly"}, setData = {nil, "storage is readonly"}, getData = "", getChecksum = ""}
local function fakeInvoke(address, name, ...)
    checkArg(1, address, "string")
    checkArg(2, name, "string")
    if address == eeprom.address then
        for key, value in pairs(eepromFakeFunctions) do
            if key == name then
                local valuetype = type(value)
                if valuetype == "table" then
                    return unpack(value)
                elseif valuetype == "function" then
                    return value(...)
                else
                    return value                    
                end
            end
        end
        return originalInvoke(address, name, ...)
    else
        return originalInvoke(address, name, ...)
    end
end

local function cryptoBios() component.invoke = fakeInvoke end
local function uncryptoBios() component.invoke = originalInvoke end

-------------------------------------------------------graphics init

local gpu = getComponent("gpu")
local screen
local keyboard
local rx, ry
local function noControl() gpu = {} setmetatable(gpu, {__index = function() error("gpu and screen required") end}) end
if not gpu then 
    noControl()
else
    screen = component.list("screen")()
    if screen then
        gpu.bind(screen)
        rx, ry = gpu.getResolution()
        keyboard = component.proxy(screen).getKeyboards()[1]
    else
        noControl()
    end
end

-------------------------------------------------------graphics

local function invert()
    gpu.setForeground(gpu.setBackground(gpu.getForeground()))
end

local function clear()
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0)
    gpu.fill(1, 1, rx, ry, " ")
end

local function setText(text, posY)
    gpu.set(math.ceil((rx / 2) - (unicode.len(text) / 2)), posY, text)
end

local function menu(label, strs, num)
    local select = num or 1
    while true do
        clear()
        local startpos = (select // ry) * ry
        if startpos == 0 then
            invert()
            setText(label, 1)
            invert()
        end
        for i = 1, #strs do
            local pos = (i + 1) - startpos
            if pos >= 1 and pos <= ry then
                if keyboard and select == i then invert() end
                setText(strs[i], pos)
                if keyboard and select == i then invert() end
            end
        end
        local eventName, uuid, _, code, button = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 200 and select > 1 then
                select = select - 1
            end
            if code == 208 and select < #strs then
                select = select + 1
            end
            if code == 28 then
                return select
            end
        elseif eventName == "touch" and uuid == screen and button == 0 then
            code = code + startpos
            code = code - 1
            if code >= 1 and code <= #strs then
                return code
            end
        elseif eventName == "scroll" and uuid == screen then
            if button == 1 and select > 1 then
                select = select - 1
            end
            if button == -1 and select < #strs then
                select = select + 1
            end
        end
    end
end

local function yesno(label)
    return menu(label, {"no", "no", "yes", "no"}) == 3
end

local function input(posX, posY)
    if not keyboard then error("keyboard required") end
    local buffer = ""
    while true do
        gpu.set(posX, posY, "_")
        local eventName, uuid, char, code = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                return buffer
            elseif code == 14 then
                if unicode.len(buffer) > 0 then
                    buffer = unicode.sub(buffer, 1, unicode.len(buffer) - 1)
                    gpu.set(posX, posY, " ")
                    posX = posX - 1
                    gpu.set(posX, posY, " ")
                end
            elseif char ~= 0 then
                buffer = buffer .. unicode.char(char)
                gpu.set(posX, posY, unicode.char(char))
                posX = posX + 1
            end
        elseif eventName == "clipboard" and uuid == keyboard then
            buffer = buffer .. char
            gpu.set(posX, posY, char)
            posX = posX + unicode.len(char)
            if unicode.sub(char, unicode.len(char), unicode.len(char)) == "\n" then
                return unicode.sub(buffer, 1, unicode.len(buffer) - 1)
            end
        end
    end
end

local function splash(str)
    clear()
    gpu.set(1, 1, str)
    gpu.set(1, 2, "press enter to continue...")
    while true do
        local eventName, uuid, _, code = computer.pullSignal()
        if eventName == "key_down" and uuid == keyboard then
            if code == 28 then
                break
            end
        end
    end
end

-------------------------------------------------------functions

local function split(str, sep)
    local parts, count = {}, 1
    for i = 1, #str do
        local char = str:sub(i, i)
        if not parts[count] then parts[count] = "" end
        if char == "\n" then
            count = count + 1
        else
            parts[count] = parts[count] .. char
        end
    end
    return parts
end

local function getFile(fs, path)
    local file, err = fs.open(path)
    if not file then return nil, err end
    local buffer = ""
    while true do
        local read = fs.read(file, math.huge)
        if not read then break end
        buffer = buffer .. read
    end
    fs.close(file)
    return buffer
end

local function saveFile(fs, path, data)
    local file, err = fs.open(path, "w")
    if not file then return nil, err end
    fs.write(file, data)
    fs.close(file)
    return true
end

local function getDataPart(part)
    return split(eeprom.getData(), "\n")[part] or ""
end

local function setDataPart(part, newdata)
    uncryptoBios()
    if newdata:find("\n") then error("\\n char") end
    parts = split(eeprom.getData(), "\n")
    for i = part, 1, -1 do
        if not parts[i] then parts[i] = "" end
    end
    parts[part] = newdata
    eeprom.setData(table.concat(parts, "\n"))
end

local function selectfs(label, uuid)
    local data = {n = {}, a = {}}
    for address in component.list("filesystem") do
        data.n[#data.n + 1] = table.concat({address:sub(1, 6), component.proxy(address).getLabel()}, ":")
        data.a[#data.a + 1] = address
    end
    data.n[#data.n + 1] = "back"
    local num = 1
    for i = 1, #data.a do 
        if data.a[i] == uuid then
            num = i
            break
        end
    end
    local select = menu(label, data.n, num)
    local address = data.a[select]
    return component.proxy(address or "") and address
end

local function bootTo(address)
    local fs, data = component.proxy(address)
    if fs.exists("/init.lua") then
        computer.getBootAddress = function() return address end
        computer.setBootAddress = function(address) setDataPart(1, address) end
        data = getFile(fs, "/init.lua")
    elseif fs.exists("/OS.lua") then
        eepromFakeFunctions.getData = address
        eepromFakeFunctions.setData = function(address) setDataPart(1, address) end
        data = getFile(fs, "/OS.lua")
    else
        error("boot file not found")
    end
    cryptoBios()
    if screen then gpu.setResolution(gpu.maxResolution()) end
    assert(xpcall(assert(load(data, "=init")), traceback))
    shutdown()
end

local function setResolution()
    if screen then
        local cx = tonumber(getDataPart(2))
        local cy = tonumber(getDataPart(3))
        if cx and cy and pcall(gpu.setResolution, cx, cy) then
            rx, ry = cx, cy
        else
            rx, ry = gpu.maxResolution()
            gpu.setResolution(rx, ry)
        end
    end
end
setResolution()

local function getInternetFile(url)
    local buffer = ""
    local file, err = internet.request(url)
    if not file then return nil, err end
    while true do
        local read = file.read(math.huge)
        if not read then break end
        buffer = buffer .. read
    end
    file.finishConnect()
    file.close()
    return buffer
end

local function checkInternet()
    if not internet then splash("internet card is not found") return true end
end

-------------------------------------------------------application

local function selectbootdevice()
    local address = selectfs("select", getDataPart(1))
    if address then
        setDataPart(1, address)
    end
end

local function fastboot()
    local address = selectfs("fastboot")
    if address then
        bootTo(address)
    end
end

local function lua()
    while true do
        clear()
        gpu.set(1, 1, "lua: ")
        local read = input(6, 1)
        if read == "" then return end
        local code, err = load(read, nil, "=lua")
        if not code then
            splash(err or "unkown")
        else
            cryptoBios()
            local ok, err = pcall(code)
            splash(tostring(err or "nil"))
        end
    end
end

local function diskMenager()
    local function main()
        local function readonlySplash(address) 
            if component.proxy(address).isReadOnly() then
                splash("drive is read only") 
                return true
            end
        end
        while true do
            local select = menu("disk menager", {"rename", "format", "install", "clone", "back"})
            if select == 1 then
                local address = selectfs("renamer")
                if address then
                    if readonlySplash(address) then break end
                    clear()
                    gpu.set(1, 1, "new name: ")
                    local read = input(11, 1)
                    if read ~= "" then
                        component.proxy(address).setLabel(read)
                    end
                end
            elseif select == 2 then
                local address = selectfs("formater")
                if address then
                    if readonlySplash(address) then break end
                    if yesno("format? "..address:sub(1, 6)) then
                        component.proxy(address).remove("/")
                    end
                end
            elseif select == 3 or select == 4 then
                local drive1 = selectfs("drive1")
                if drive1 then
                    local drive2 = selectfs("drive2")
                    if drive2 and yesno(((select == 3 and "install") or "clone").." from "..drive1:sub(1, 6).." to "..drive2:sub(1, 6).."?") then
                        local drive1 = component.proxy(drive1)
                        local drive2 = component.proxy(drive2)
                        if select == 4 then drive2.remove("/") end
                        local function fsname(path)
                            local data = ""
                            for substring in path:gmatch("[^/\\]+") do
                                data = substring
                            end
                            return data
                        end
                        local function copy(fs1, fs2, path, install)
                            for _, data in ipairs(fs1.list(path)) do
                                local fullPath = path..data
                                if fsname(fullPath):sub(1, 1) ~= "." or not install then
                                    if fs1.isDirectory(fullPath) then
                                        fs2.makeDirectory(fullPath)
                                        copy(fs1, fs2, fullPath, install)
                                    else
                                        assert(saveFile(fs2, fullPath, assert(getFile(fs1, fullPath))))
                                    end
                                end
                            end
                        end
                        copy(drive1, drive2, "/", select == 3)
                    end
                end
            elseif select == 5 then
                return
            end
        end
    end
    local ok, err = pcall(main)
    if not ok then splash(err or "unkown") end
end

local function internetBoot()
    if checkInternet() then return end
    while true do
        clear()
        gpu.set(1, 1, "url: ")
        local url = input(6, 1)
        
        if url == "" then return end
        local buffer, err = getInternetFile(url)
        if not buffer then splash(err or "unkown") return end

        cryptoBios()
        computer.getBootAddress = function() return url end
        assert(xpcall(assert(load(buffer, "=internetfile")), traceback))
        shutdown()
    end
end

local function resolution()
    local resolutions = {{80, 25}, {50, 16}, {25, 8}, {64, 32}, {32, 16}, {40, 20}, {20, 10}}
    local strs = {}
    for i = 1, #resolutions do
        strs[i] = table.concat(resolutions[i], "x")
    end
    strs[#strs + 1] = "clear"
    strs[#strs + 1] = "back"
    while true do
        local select = menu("resolution", strs)
        if select > #resolutions then
            select = select - #resolutions
            if select == 1 then
                setDataPart(2, "")
                setDataPart(3, "")
                setResolution()
            elseif select == 2 then
                return
            end
        else
            local cx, cy = table.unpack(resolutions[select])
            setDataPart(2, tostring(cx))
            setDataPart(3, tostring(cy))
            setResolution()
        end
    end
end

local function biosUpdate()
    if checkInternet() then return end
    local file, err = getInternetFile("")
    if not file then splash(err or "unkown") return end
    uncryptoBios()
    if file ~= eeprom.get() then
        eeprom.set(file)
    end
end

local function mainmenu()
    while true do
        local select = menu("top bios v5", {"select", "fastboot", "diskMenager", "resolution", "internetBoot", "lua", "shutdown", "reboot", "back"})
        if select == 1 then
            selectbootdevice()
        elseif select == 2 then
            fastboot()
        elseif select == 3 then
            diskMenager()
        elseif select == 4 then
            resolution()
        elseif select == 5 then
            internetBoot()
        elseif select == 6 then
            lua()
        elseif select == 7 then
            shutdown()
        elseif select == 8 then
            shutdown(true)
        elseif select == 9 then
            return
        end
    end
end

-------------------------------------------------------main

biosUpdate()

if screen and component.proxy(getDataPart(1)) then
    clear()
    gpu.set(1, 1, "boot: " .. getDataPart(1):sub(1, 6))
    gpu.set(1, 2, "MENU-alt")
    gpu.set(1, 3, "BOOT-enter")
    for i = 1, 25 do
        local eventName, uuid, _, code, button = computer.pullSignal(0.1)
        if eventName == "key_down" and uuid == keyboard then
            if code == 56 then
                mainmenu()
                break
            elseif code == 28 then
                break
            end
        elseif eventName == "touch" and uuid == screen and button == 0 then
            if code == 2 then
                mainmenu()
                break
            elseif code == 3 then
                break
            end
        end
    end
end

while not component.proxy(getDataPart(1)) do
    mainmenu()
end
bootTo(getDataPart(1))