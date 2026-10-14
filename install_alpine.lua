#!/usr/bin/env lua5.4

-- Rama-OI
-- Alpine Linux x86 (32-bit) | Minimal Xorg + i3
-- Usage:
--   lua5.4 install_alpine.lua install
--   lua5.4 install_alpine.lua apply
--   lua5.4 install_alpine.lua check
--   lua5.4 install_alpine.lua uninstall

local VERSION = "1.0.0"

local HOME = assert(os.getenv("HOME"), "HOME is not set")
local USER = assert(os.getenv("USER"), "USER is not set")

local ROOT = HOME .. "/.local/share/rama-oi"
local CONFIG = ROOT .. "/config"
local BIN = ROOT .. "/bin"
local LOCAL_BIN = HOME .. "/.local/bin"

local function log(message)
    print("\27[1;35m==>\27[0m " .. message)
end

local function fail(message)
    io.stderr:write("\27[1;31mError:\27[0m " .. message .. "\n")
    os.exit(1)
end

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(args, quiet)
    local parts = {}

    for _, value in ipairs(args) do
        parts[#parts + 1] = quote(value)
    end

    local command = table.concat(parts, " ")

    if not quiet then
        log(command)
    end

    local ok, reason, code = os.execute(command)

    if ok == true then
        return true
    end

    if quiet then
        return false
    end

    fail(("Command failed (%s, %s): %s"):format(
        tostring(reason), tostring(code), command
    ))
end

local function succeeds(command)
    return os.execute(command .. " >/dev/null 2>&1") == true
end

local function exists(path)
    return succeeds("test -e " .. quote(path))
        or succeeds("test -L " .. quote(path))
end

local function is_link(path)
    return succeeds("test -L " .. quote(path))
end

local function read_link(path)
    local handle = io.popen("readlink " .. quote(path) .. " 2>/dev/null")
    if not handle then
        return nil
    end

    local result = handle:read("*l")
    handle:close()
    return result
end

local function mkdir(path)
    run({ "mkdir", "-p", path })
end

local function write_file(path, content, mode)
    local file, err = io.open(path, "w")

    if not file then
        fail("Cannot write " .. path .. ": " .. tostring(err))
    end

    file:write(content)
    file:close()

    if mode then
        run({ "chmod", mode, path })
    end
end

local function read_file(path)
    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local result = file:read("*a")
    file:close()
    return result
end

-- ------------------------------------------------------------
-- Privilege escalation
-- ------------------------------------------------------------

local PRIVILEGE

if succeeds("command -v doas") then
    PRIVILEGE = "doas"
elseif succeeds("command -v sudo") then
    PRIVILEGE = "sudo"
else
    fail("Neither doas nor sudo is installed. Run the bootstrap first.")
end

local function privileged(args)
    local command = { PRIVILEGE }

    for _, value in ipairs(args) do
        command[#command + 1] = value
    end

    run(command)
end

-- ------------------------------------------------------------
-- Validation
-- ------------------------------------------------------------

local function validate()
    if not exists("/etc/alpine-release") then
        fail("This installer requires Alpine Linux.")
    end

    if USER == "root" then
        fail("Run this installer as your normal user, not root.")
    end

    local handle = io.popen("apk --print-arch 2>/dev/null")
    local arch = handle and handle:read("*l")

    if handle then
        handle:close()
    end

    if arch ~= "x86" then
        fail("Expected 32-bit Alpine x86; detected " .. tostring(arch))
    end

    if not succeeds(
        "id -nG " .. quote(USER)
        .. " | grep -Eq '(^| )wheel( |$)'"
    ) then
        fail("Your user must belong to the wheel group for doas/sudo.")
    end
end

-- ------------------------------------------------------------
-- Package groups
-- ------------------------------------------------------------

local packages = {
    desktop = {
        "xorg-server",
        "xinit",
        "xauth",
        "dbus",
        "dbus-x11",
        "i3wm",
        "i3status",
        "dmenu",
        "xterm",
        "font-dejavu",
        "xf86-input-libinput",
        "mesa"
        "caja"
    },

    utilities = {
        -- "git",
        -- "curl",
        -- "ca-certificates",
        -- "mousepad",
        "less",
        "nano",
        "mc",
        "tree",
        "unzip",
        "zip",
        "jq",
    },
}

local function enable_community()
    local release = read_file("/etc/alpine-release")
    local branch = release and release:match("^(%d+%.%d+)")

    if not branch then
        fail("Cannot determine Alpine release version.")
    end

    local path = "/etc/apk/repositories"
    local content = read_file(path)

    if not content then
        fail("Cannot read " .. path)
    end

    local active = false
    local commented = false

    for line in content:gmatch("[^\r\n]+") do
        if line:match("/community/?%s*$") then
            if line:match("^%s*#") then
                commented = true
            else
                active = true
            end
        end
    end

    if active then
        return
    end

    if commented then
        privileged({
            "sed", "-i",
            "/\\/community/s/^[[:space:]]*#//",
            path,
        })
    else
        local repository =
            "https://dl-cdn.alpinelinux.org/alpine/v"
            .. branch .. "/community"

        local file, err = io.open(path, "a")

        if not file then
            fail("Cannot update repositories: " .. tostring(err))
        end

        file:write("\n" .. repository .. "\n")
        file:close()
    end
end

local function install_packages()
    local selected = {}

    for _, group in ipairs({ "desktop", "utilities" }) do
        for _, package in ipairs(packages[group]) do
            selected[#selected + 1] = package
        end
    end

    privileged({ "apk", "update" })

    local args = { "apk", "add", "--no-cache" }

    for _, package in ipairs(selected) do
        args[#args + 1] = package
    end

    privileged(args)
end

-- ------------------------------------------------------------
-- OpenRC services and user groups
-- ------------------------------------------------------------

local function configure_system()
    privileged({ "rc-update", "add", "dbus", "default" })

    local group_file = read_file("/etc/group") or ""
    local known = {}

    for line in group_file:gmatch("[^\r\n]+") do
        local name = line:match("^([^:]+):")
        if name then
            known[name] = true
        end
    end

    local handle = io.popen("id -nG " .. quote(USER))
    local current = {}

    if handle then
        for group in (handle:read("*a") or ""):gmatch("%S+") do
            current[group] = true
        end
        handle:close()
    end

    for _, group in ipairs({ "input", "video", "audio" }) do
        if known[group] and not current[group] then
            privileged({ "addgroup", USER, group })
        end
    end
end

-- ------------------------------------------------------------
-- Managed directories and links
-- ------------------------------------------------------------

local function create_directories()
    for _, path in ipairs({
        ROOT,
        CONFIG .. "/i3",
        CONFIG .. "/i3status",
        BIN,
        LOCAL_BIN,
        HOME .. "/.config/i3",
        HOME .. "/.config/i3status",
    }) do
        mkdir(path)
    end
end

local function link(target, destination)
    if is_link(destination) then
        local current = read_link(destination)

        if current == target then
            return
        end

        if current and current:sub(1, #ROOT + 1) == ROOT .. "/" then
            run({ "rm", destination })
        else
            fail("Refusing to replace unrelated symlink: " .. destination)
        end
    elseif exists(destination) then
        fail(
            "File already exists: " .. destination
            .. "\nBack it up before running the installer again."
        )
    end

    run({ "ln", "-s", target, destination })
end

-- ------------------------------------------------------------
-- i3 configuration
-- ------------------------------------------------------------

local function generate_i3()
    local content = [=[
set $mod Mod4
font pango:DejaVu Sans Mono 9

# Catppuccin Mocha
client.focused          #cba6f7 #313244 #cdd6f4 #cba6f7 #313244
client.unfocused        #1e1e2e #1e1e2e #a6adc8 #313244 #1e1e2e
client.urgent           #f38ba8 #f38ba8 #11111b #f38ba8 #f38ba8

default_border pixel 1
default_floating_border pixel 1
gaps inner 4
gaps outer 2

# Applications
bindsym $mod+Return exec xterm
bindsym $mod+d exec dmenu_run

# Window controls
bindsym $mod+Shift+q kill
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exit

# Focus
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Move containers
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

# Workspaces
]=]

    for n = 1, 9 do
        content = content
            .. ("bindsym $mod+%d workspace number %d\n"):format(n, n)
            .. ("bindsym $mod+Shift+%d move container to workspace number %d\n"):format(n, n)
    end

    content = content .. [[

bar {
    position bottom
    status_command i3status
    colors {
        background #1e1e2e
        statusline #cdd6f4
        separator #a6adc8
        focused_workspace #89b4fa #89b4fa #11111b
        active_workspace #313244 #313244 #cdd6f4
        inactive_workspace #1e1e2e #1e1e2e #a6adc8
        urgent_workspace #f38ba8 #f38ba8 #11111b
    }
}
]]

    write_file(CONFIG .. "/i3/config", content)
end

-- ------------------------------------------------------------
-- i3status configuration
-- ------------------------------------------------------------

local function generate_i3status()
    write_file(CONFIG .. "/i3status/config", [=[
general {
    colors = true
    interval = 5
    color_good = "#a6e3a1"
    color_degraded = "#fab387"
    color_bad = "#f38ba8"
}

order += "cpu_usage"
order += "memory"
order += "tztime local"

cpu_usage {
    format = "CPU: %usage"
}

memory {
    format = "RAM: %used"
}

tztime local {
    format = "%Y-%m-%d %H:%M"
}
]=])
end

-- ------------------------------------------------------------
-- X session
-- ------------------------------------------------------------

local function generate_xinitrc()
    local path = HOME .. "/.xinitrc"

    if exists(path) then
        log("Keeping existing " .. path)
        return
    end

    write_file(path, [=[
#!/bin/sh
exec dbus-run-session i3
]=])
end

-- ------------------------------------------------------------
-- Apply configuration
-- ------------------------------------------------------------

local function apply()
    create_directories()
    generate_i3()
    generate_i3status()
    generate_xinitrc()

    link(CONFIG .. "/i3/config", HOME .. "/.config/i3/config")
    link(
        CONFIG .. "/i3status/config",
        HOME .. "/.config/i3status/config"
    )

    log("Configuration applied.")
end

-- ------------------------------------------------------------
-- Validation
-- ------------------------------------------------------------

local function check()
    local failed = false

    for _, command in ipairs({
        "apk",
        "startx",
        "i3",
        "i3status",
        "dmenu_run",
        "xterm",
        "dbus-run-session",
    }) do
        if succeeds("command -v " .. quote(command)) then
            print("[OK]      " .. command)
        else
            print("[MISSING] " .. command)
            failed = true
        end
    end

    for _, path in ipairs({
        CONFIG .. "/i3/config",
        CONFIG .. "/i3status/config",
        HOME .. "/.xinitrc",
    }) do
        if exists(path) then
            print("[OK]      " .. path)
        else
            print("[MISSING] " .. path)
            failed = true
        end
    end

    if failed then
        os.exit(1)
    end

    log("All checks passed.")
end

-- ------------------------------------------------------------
-- Uninstall managed configuration
-- ------------------------------------------------------------

local function uninstall()
    local links = {
        { CONFIG .. "/i3/config", HOME .. "/.config/i3/config" },
        {
            CONFIG .. "/i3status/config",
            HOME .. "/.config/i3status/config",
        },
    }

    for _, item in ipairs(links) do
        if is_link(item[2]) and read_link(item[2]) == item[1] then
            run({ "rm", item[2] })
        end
    end

    io.write("Remove Rama-OI files at " .. ROOT .. "? [y/N] ")
    local answer = (io.read("*l") or ""):lower()

    if answer == "y" or answer == "yes" then
        if ROOT == HOME .. "/.local/share/rama-oi" then
            run({ "rm", "-rf", "--", ROOT })
        else
            fail("Unexpected installation path; refusing removal.")
        end
    end

    log("Uninstall completed. System packages were not removed.")
end

-- ------------------------------------------------------------
-- CLI
-- ------------------------------------------------------------

local action = arg[1] or "install"

if action == "install" then
    validate()
    enable_community()
    install_packages()
    configure_system()
    apply()

    print("")
    log("Rama-OI installation completed.")
    print("Start the desktop with: startx")

elseif action == "apply" then
    validate()
    apply()

elseif action == "check" then
    validate()
    check()

elseif action == "uninstall" then
    uninstall()

else
    io.stderr:write(([=[
Rama-OI %s - Alpine Linux x86

Usage:
    lua5.4 install_alpine.lua install
    lua5.4 install_alpine.lua apply
    lua5.4 install_alpine.lua check
    lua5.4 install_alpine.lua uninstall
]=]):format(VERSION))

    os.exit(2)
end