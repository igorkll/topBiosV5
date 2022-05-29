_G.smartEfi = true
computer.pullSignal(0.1)
computer.setArchitecture("Lua 5.3")

internet = component.proxy(component.list("internet")() or "")
local eeprom = component.proxy(component.list("eeprom")() or "")

function getInternetFile(url)--взято из mineOS efi от игорь тимофеев
    local handle, data, result, reason = internet.request(url), ""
    if handle then
        while 1 do
            result, reason = handle.read(math_huge)	
            if result then
                data = data .. result
            else
                handle.close()
                
                if reason then
                    return nil, reason
                else
                    return data
                end
            end
        end
    else
        return nil, "Unvalid Address"
    end
end

function getFile(fs, path)
    local file, err = fs.open(path, "rb")
    if not file then return nil, err end
    local buffer = ""
    while 1 do
        local read = fs.read(file, math.huge)
        if not read then break end
        buffer = buffer .. read
    end
    fs.close(file)
    return buffer
end

function saveFile(fs, path, data)
    local file, err = fs.open(path, "wb")
    if not file then return nil, err end
    fs.write(file, data)
    fs.close(file)
    return true
end

device = computer.getDeviceInfo()

local updateFile
if internet then
    updateFile = getInternetFile("https://raw.githubusercontent.com/igorkll/topBiosV5/main/smartEfi.bin")
    if not updateFile then
        internet = nil
    else
        local updateChip = getInternetFile("https://raw.githubusercontent.com/igorkll/topBiosV5/main/smartEfiLoader.bin")
        if updateChip and updateChip ~= eeprom.get() then
            if eeprom.set(updateChip) then
                computer.shutdown(true)
            end
        end
    end
end

local function checkDrive(driveProxy)
    return not driveProxy.isReadOnly() and ((driveProxy.spaceTotal() - driveProxy.spaceUsed()) > (1024 * 64)) and driveProxy.slot > 0
end

local driveProxy = component.proxy(eeprom.getData())
if not driveProxy or driveProxy.address == computer.tmpAddress() or not driveProxy.exists("/.efi") then
    driveProxy = nil
    for address in component.list("filesystem") do
        if device[address].clock ~= "20/20/20" then
            driveProxy = component.proxy(address)
            if checkDrive(driveProxy) then
                break
            else
                driveProxy = nil
            end
        end
    end
    if not driveProxy then
        driveProxy = component.proxy(computer.tmpAddress())
    end
    if eeprom.getData() ~= driveProxy.address then
        eeprom.setData(driveProxy.address)
    end
end

function eeprom_setData(data)
    assert(saveFile(driveProxy, "/.efiData", data))
end

function eeprom_getData()
    if driveProxy.exists("/.efiData") then
        return assert(getFile(driveProxy, "/.efiData"))
    else
        return ""
    end
end

if updateFile then
    saveFile(driveProxy, "/.efi", updateFile)
else
    updateFile = getFile(driveProxy, "/.efi")

    if not updateFile then
        error("no internet card found and .efi file, attach internet card or old drive", 0)
    end
end

assert(load(updateFile))()