#!/usr/bin/env lua5.4

-- ============================================================
-- Rama-OI
-- Alpine Linux x86 (32-bit) | Minimal Xorg + i3 | Coqui
-- ============================================================

local VERSION = "1.1.0"

local HOME = assert(os.getenv("HOME"), "HOME is not set")
local USER = assert(os.getenv("USER"), "USER is not set")

local ROOT = HOME .. "/.local/share/rama-oi"
local CONFIG = ROOT .. "/config"
local BIN = ROOT .. "/bin"
local SRC = ROOT .. "/src"
local LOCAL_BIN = HOME .. "/.local/bin"

local COQUI_REPO = "https://github.com/rama-oi/coqui.git"
local COQUI_REV = "cb4c3353f41d4a1c536cd927ad03338a7498d632"

local COQUI_DIR = SRC .. "/coqui"
local COQUI_BIN = BIN .. "/coqui"

-- ============================================================
-- Theme
-- ============================================================

local theme = {
    name = "catppuccin-mocha",

    colors = {
        bg = "#1e1e2e",
        bg_dark = "#11111b",
        bg_alt = "#313244",
        fg = "#cdd6f4",
        muted = "#a6adc8",
        accent = "#cba6f7",
        blue = "#89b4fa",
        danger = "#f38ba8",
        warning = "#fab387",
        success = "#a6e3a1",
    },

    font = {
        family = "DejaVu Sans Mono",
        size = 9,
    },

    spacing = {
        inner = 4,
        outer = 2,
    },
}

-- ============================================================
-- Package definitions
-- ============================================================

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
        "mesa",
        "caja",
        "dunst",
        "libnotify",
        "mousepad",
    },

    build = {
        "build-base",
        "git",
        "curl",
        "ca-certificates",
        "pkgconf",
        "linux-headers",
        "libx11-dev",
        "libxkbcommon-dev",
        "openssl-dev",
        "zlib-dev",
        "rust",
        "cargo",
    },

    utilities = {
        "less",
        "nano",
        "mc",
        "tree",
        "unzip",
        "zip",
        "jq",
        "btop",
        "cmus",
        "vlc",
    },
}

local enabled_packages = {
    "desktop",
    "build",
    "utilities",
}

-- ============================================================
-- Application definitions
-- ============================================================

local applications = {
    {
        category = "Utilities",
        label = "Terminal",
        command = "xterm",
        terminal = false,
    },
    {
        category = "Utilities",
        label = "Mousepad",
        command = "mousepad",
        terminal = false,
    },
    {
        category = "Utilities",
        label = "File Manager",
        command = "caja",
        terminal = false,
    },
    {
        category = "Utilities",
        label = "Midnight Commander",
        command = "mc",
        terminal = true,
    },
    {
        category = "Utilities",
        label = "Btop",
        command = "btop",
        terminal = true,
    },
    {
        category = "Networking",
        label = "Impala",
        command = "impala",
        terminal = true,
        optional = true,
    },
    {
        category = "Networking",
        label = "Bluetui",
        command = "bluetui",
        terminal = true,
        optional = true,
    },
    {
        category = "Networking",
        label = "Wiremix",
        command = "wiremix",
        terminal = true,
        optional = true,
    },
    {
        category = "Multimedia",
        label = "Cmus",
        command = "cmus",
        terminal = true,
    },
    {
        category = "Multimedia",
        label = "VLC",
        command = "vlc",
        terminal = false,
    },
    {
        category = "System",
        label = "i3 Exit",
        command = "i3-msg exit",
        terminal = false,
    },
    {
        category = "System",
        label = "Reboot",
        command = "reboot",
        terminal = false,
    },
    {
        category = "System",
        label = "Shutdown",
        command = "poweroff",
        terminal = false,
    },
}

-- ============================================================
-- Helpers
-- ============================================================

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
        tostring(reason),
        tostring(code),
        command
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

local function toml_quote(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\n", "\\n")

    return '"' .. value .. '"'
end

-- ============================================================
-- Privilege escalation
-- ============================================================

local PRIVILEGE

if succeeds("command -v doas") then
    PRIVILEGE = "doas"
elseif succeeds("command -v sudo") then
    PRIVILEGE = "sudo"
else
    fail("Neither doas nor sudo is installed. Bootstrap one first.")
end

local function privileged(args)
    local command = { PRIVILEGE }

    for _, value in ipairs(args) do
        command[#command + 1] = value
    end

    run(command)
end

-- ============================================================
-- Validation
-- ============================================================

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

-- ============================================================
-- Alpine repositories
-- ============================================================

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
            "sed",
            "-i",
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

-- ============================================================
-- Package management
-- ============================================================

local function install_packages()
    local selected = {}
    local seen = {}

    for _, group in ipairs(enabled_packages) do
        local list = packages[group]

        if not list then
            fail("Unknown package group: " .. group)
        end

        for _, package in ipairs(list) do
            if not seen[package] then
                selected[#selected + 1] = package
                seen[package] = true
            end
        end
    end

    log("Updating Alpine package indexes")
    privileged({ "apk", "update" })

    local args = { "apk", "add", "--no-cache" }

    for _, package in ipairs(selected) do
        args[#args + 1] = package
    end

    privileged(args)
end

-- ============================================================
-- Rust toolchain: rustup + stable Rust + Cargo
-- ============================================================

local function install_rust()
    log("Installing Alpine Rust toolchain")

    privileged({
        "apk",
        "add",
        "--no-cache",
        "rust",
        "cargo",
    })

    if not succeeds("command -v cargo")
        or not succeeds("command -v rustc") then
        fail("Alpine Rust packages did not install correctly.")
    end

    run({ "cargo", "--version" })
    run({ "rustc", "--version" })

    log("Rust toolchain is ready")
end

-- ============================================================
-- Coqui build and installation
-- ============================================================

local function build_coqui()
    log("Preparing Coqui source")

    if not exists(COQUI_DIR .. "/.git") then
        if exists(COQUI_DIR) then
            fail("Coqui source exists but is not a Git repository.")
        end

        mkdir(SRC)

        run({
            "git",
            "clone",
            COQUI_REPO,
            COQUI_DIR,
        })
    end

    log("Fetching Coqui revision")

    run({
        "git",
        "-C",
        COQUI_DIR,
        "fetch",
        "origin",
        COQUI_REV,
    })

    run({
        "git",
        "-C",
        COQUI_DIR,
        "checkout",
        "--detach",
        COQUI_REV,
    })

    local cargo = "cargo"
    local path = os.getenv("PATH") or ""

    log("Building Coqui in release mode")

    run({
        "env",
        "PATH=" .. path,
        cargo,
        "build",
        "--release",
        "--manifest-path",
        COQUI_DIR .. "/Cargo.toml",
    })

    local built = COQUI_DIR .. "/target/release/coqui"

    if not exists(built) then
        fail(
            "Coqui build did not produce the expected binary:\n"
            .. built
        )
    end

    mkdir(BIN)

    log("Installing Coqui binary")

    run({
        "install",
        "-m",
        "0755",
        built,
        COQUI_BIN,
    })

    log("Coqui installed successfully: " .. COQUI_BIN)
end

-- ============================================================
-- Managed directories and symlinks
-- ============================================================

local function create_directories()
    for _, path in ipairs({
        ROOT,
        CONFIG .. "/i3",
        CONFIG .. "/i3status",
        CONFIG .. "/rama",
        BIN,
        SRC,
        LOCAL_BIN,
        HOME .. "/.config/i3",
        HOME .. "/.config/i3status",
        HOME .. "/.config/rama",
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
            "Existing file will not be overwritten: " .. destination
            .. "\nBack it up or move it manually, then retry."
        )
    end

    run({ "ln", "-s", target, destination })
end

-- ============================================================
-- Launcher scripts
-- ============================================================

local function generate_scripts()
    write_file(
        BIN .. "/rama-coqui-launch",
        ([=[
#!/bin/sh
exec xterm -class floating-terminal -e %q
]=]):format(COQUI_BIN),
        "0755"
    )

    write_file(
        BIN .. "/rama-power-menu",
        [=[
#!/bin/sh

choice=$(
    printf '%s\n' "Shutdown" "Reboot" "Logout" |
        dmenu -i -p "Power:"
)

case "$choice" in
    Shutdown) poweroff ;;
    Reboot)   reboot ;;
    Logout)   i3-msg exit ;;
esac
]=],
        "0755"
    )

    for _, name in ipairs({
        "coqui",
        "rama-coqui-launch",
        "rama-power-menu",
    }) do
        link(BIN .. "/" .. name, LOCAL_BIN .. "/" .. name)
    end
end

-- ============================================================
-- Coqui configuration generator
-- ============================================================

local function generate_coqui()
    local lines = {
        'theme = "nixos"',
        "",
    }

    local previous_category = nil

    for _, app in ipairs(applications) do
        local available = not app.optional
            or succeeds("command -v " .. quote(app.command))

        if available then
            if app.category ~= previous_category then
                lines[#lines + 1] = "[[command]]"
                lines[#lines + 1] = "label = "
                    .. toml_quote("------ " .. app.category)
                lines[#lines + 1] = ""

                previous_category = app.category
            end

            local command = app.command

            if app.terminal then
                command = "xterm -e " .. command
            end

            lines[#lines + 1] = "[[command]]"
            lines[#lines + 1] = "label = " .. toml_quote(app.label)
            lines[#lines + 1] = "cmd = " .. toml_quote(command)
            lines[#lines + 1] = 'description = ""'
            lines[#lines + 1] = ""
        end
    end

    write_file(
        CONFIG .. "/rama/coqui_config.toml",
        table.concat(lines, "\n")
    )
end

-- ============================================================
-- i3 configuration
-- ============================================================

local function generate_i3()
    local c = theme.colors

    local lines = {
        "set $mod Mod4",
        "",
        ("font pango:%s %d"):format(theme.font.family, theme.font.size),
        "",
        "# Catppuccin Mocha",
        ("client.focused          %s %s %s %s %s"):format(
            c.accent, c.bg_alt, c.fg, c.accent, c.bg_alt
        ),
        ("client.unfocused        %s %s %s %s %s"):format(
            c.bg, c.bg, c.muted, c.bg_alt, c.bg
        ),
        ("client.urgent           %s %s %s %s %s"):format(
            c.danger, c.danger, c.bg_dark, c.danger, c.danger
        ),
        "",
        "default_border pixel 1",
        "default_floating_border pixel 1",
        ("gaps inner %d"):format(theme.spacing.inner),
        ("gaps outer %d"):format(theme.spacing.outer),
        "",
        "# Startup",
        "exec --no-startup-id dunst",
        "",
        "# Application launcher",
        "bindsym $mod+space exec --no-startup-id rama-coqui-launch",
        "bindsym $mod+Return exec --no-startup-id xterm",
        "bindsym $mod+d exec --no-startup-id dmenu_run",
        "",
        "# Window controls",
        "bindsym $mod+Shift+q kill",
        "bindsym $mod+Shift+c reload",
        "bindsym $mod+Shift+r restart",
        "bindsym $mod+Shift+e exec --no-startup-id rama-power-menu",
        "",
        "# Focus",
        "bindsym $mod+h focus left",
        "bindsym $mod+j focus down",
        "bindsym $mod+k focus up",
        "bindsym $mod+l focus right",
        "",
        "# Move containers",
        "bindsym $mod+Shift+h move left",
        "bindsym $mod+Shift+j move down",
        "bindsym $mod+Shift+k move up",
        "bindsym $mod+Shift+l move right",
        "",
        "# Floating terminal",
        'for_window [class="^floating-terminal$"] floating enable, resize set 350 400, move position center',
        "",
        "# Workspaces",
    }

    for n = 1, 9 do
        lines[#lines + 1] = (
            "bindsym $mod+%d workspace number %d"
        ):format(n, n)

        lines[#lines + 1] = (
            "bindsym $mod+Shift+%d move container to workspace number %d"
        ):format(n, n)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "bar {"
    lines[#lines + 1] = "    position bottom"
    lines[#lines + 1] = "    status_command i3status"
    lines[#lines + 1] = "    colors {"
    lines[#lines + 1] = "        background " .. c.bg
    lines[#lines + 1] = "        statusline " .. c.fg
    lines[#lines + 1] = "        separator " .. c.muted
    lines[#lines + 1] = ("        focused_workspace %s %s %s"):format(
        c.blue, c.blue, c.bg_dark
    )
    lines[#lines + 1] = ("        active_workspace %s %s %s"):format(
        c.bg_alt, c.bg_alt, c.fg
    )
    lines[#lines + 1] = ("        inactive_workspace %s %s %s"):format(
        c.bg, c.bg, c.muted
    )
    lines[#lines + 1] = ("        urgent_workspace %s %s %s"):format(
        c.danger, c.danger, c.bg_dark
    )
    lines[#lines + 1] = "    }"
    lines[#lines + 1] = "}"

    write_file(CONFIG .. "/i3/config", table.concat(lines, "\n"))
end

-- ============================================================
-- i3status configuration
-- ============================================================

local function generate_i3status()
    local c = theme.colors

    write_file(CONFIG .. "/i3status/config", ([=[
general {
    colors = true
    interval = 5
    color_good = "%s"
    color_degraded = "%s"
    color_bad = "%s"
}

order += "cpu_usage"
order += "memory"
order += "tztime local"

cpu_usage {
    format = "CPU: %%usage"
}

memory {
    format = "RAM: %%used"
}

tztime local {
    format = "%%Y-%%m-%%d %%H:%%M"
}
]=]):format(c.success, c.warning, c.danger))
end

-- ============================================================
-- X session
-- ============================================================

local function generate_xinitrc()
    local path = HOME .. "/.xinitrc"

    if exists(path) then
        log("Keeping existing " .. path)
        return
    end

    write_file(path, [=[
#!/bin/sh
exec dbus-run-session i3
]=], "0755")
end

-- ============================================================
-- OpenRC services and user groups
-- ============================================================

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

-- ============================================================
-- Apply configuration
-- ============================================================

local function apply()
    create_directories()
    generate_scripts()
    generate_coqui()
    generate_i3()
    generate_i3status()
    generate_xinitrc()

    link(
        CONFIG .. "/i3/config",
        HOME .. "/.config/i3/config"
    )

    link(
        CONFIG .. "/i3status/config",
        HOME .. "/.config/i3status/config"
    )

    link(
        CONFIG .. "/rama/coqui_config.toml",
        HOME .. "/.config/rama/coqui_config.toml"
    )

    log("Configuration applied.")
end

-- ============================================================
-- Validation
-- ============================================================

local function check()
    local failed = false

    local cargo_bin = HOME .. "/.cargo/bin"
    local path = cargo_bin .. ":" .. (os.getenv("PATH") or "")

    for _, command in ipairs({
        "lua5.4",
        "apk",
        "git",
        "curl",
        "cargo",
        "rustc",
        "xinit",
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

    for _, command in ipairs({
        cargo_bin .. "/cargo",
        cargo_bin .. "/rustc",
        COQUI_BIN,
    }) do
        if exists(command) then
            print("[OK]      " .. command)
        else
            print("[MISSING] " .. command)
            failed = true
        end
    end

    for _, path_to_check in ipairs({
        CONFIG .. "/i3/config",
        CONFIG .. "/i3status/config",
        CONFIG .. "/rama/coqui_config.toml",
        HOME .. "/.xinitrc",
    }) do
        if exists(path_to_check) then
            print("[OK]      " .. path_to_check)
        else
            print("[MISSING] " .. path_to_check)
            failed = true
        end
    end

    if failed then
        os.exit(1)
    end

    log("All checks passed.")
end

-- ============================================================
-- Uninstall managed configuration
-- ============================================================

local function uninstall()
    local links = {
        { CONFIG .. "/i3/config", HOME .. "/.config/i3/config" },
        {
            CONFIG .. "/i3status/config",
            HOME .. "/.config/i3status/config",
        },
        {
            CONFIG .. "/rama/coqui_config.toml",
            HOME .. "/.config/rama/coqui_config.toml",
        },
        { BIN .. "/coqui", LOCAL_BIN .. "/coqui" },
        {
            BIN .. "/rama-coqui-launch",
            LOCAL_BIN .. "/rama-coqui-launch",
        },
        {
            BIN .. "/rama-power-menu",
            LOCAL_BIN .. "/rama-power-menu",
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

    log("Uninstall completed. System packages and Rust were not removed.")
end

-- ============================================================
-- CLI
-- ============================================================

local action = arg[1] or "install"

if action == "install" then
    validate()
    enable_community()
    install_packages()
    configure_system()
    install_rust()
    build_coqui()
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