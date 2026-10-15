#!/usr/bin/env lua5.4

-- ============================================================
-- Rama-OI
-- Debian 12 | X11 | i3 | st | Coqui
-- ============================================================

local VERSION = "1.0.0"

local HOME = assert(os.getenv("HOME"), "HOME is not set")
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
        size = 10,
    },

    spacing = {
        inner = 8,
        outer = 4,
    },
}

-- ============================================================
-- Package definitions
-- ============================================================

local packages = {
    desktop = {
        "i3",
        "i3status",
        "dunst",
        "libnotify-bin",
        "stterm",
        "xorg",
        "xinit",
        "dbus-x11",
        "fonts-dejavu-core",
    },

    build = {
        "build-essential",
        "git",
        "curl",
        "ca-certificates",
        "pkg-config",
        "libx11-dev",
        "libxkbcommon-dev",
    },

    multimedia = {
        "vlc"
    },

    utilities = {
        "mc",
        "btop",
        "mousepad",
        "cmus",
        "tree",
        "jq",
        "unzip",
        "zip",
    },
}

-- Install only these groups by default.
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
        command = "st",
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
        command = "systemctl reboot",
        terminal = false,
    },
    {
        category = "System",
        label = "Shutdown",
        command = "systemctl poweroff",
        terminal = false,
    },
}

-- ============================================================
-- Keybindings
-- ============================================================

local keybindings = {
    { key = "Mod4+space", command = "rama-coqui-launch" },
    { key = "Mod4+z", command = "st" },
    { key = "Mod4+Return", command = "st" },
    { key = "Mod4+x", command = "kill" },
    { key = "Mod4+r", command = "reload" },
    { key = "Mod4+Escape", command = "rama-power-menu" },
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

local function run(args)
    local command = {}

    for _, arg in ipairs(args) do
        command[#command + 1] = quote(arg)
    end

    local line = table.concat(command, " ")
    log(line)

    local ok, reason, code = os.execute(line)

    if ok ~= true then
        fail(("Command failed (%s, %s): %s"):format(
            tostring(reason),
            tostring(code),
            line
        ))
    end
end

local function succeeds(command)
    local ok = os.execute(command .. " >/dev/null 2>&1")
    return ok == true
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

    local value = handle:read("*l")
    handle:close()
    return value
end

local function mkdir(path)
    run({ "mkdir", "-p", path })
end

local function write_file(path, content, mode)
    local handle, err = io.open(path, "w")
    if not handle then
        fail("Cannot write " .. path .. ": " .. tostring(err))
    end

    handle:write(content)
    handle:close()

    if mode then
        run({ "chmod", mode, path })
    end
end

local function link(target, destination)
    if is_link(destination) then
        local current = read_link(destination)

        if current == target then
            return
        end

        -- Replace only links that point into our managed directory.
        if current and current:sub(1, #ROOT + 1) == ROOT .. "/" then
            run({ "rm", destination })
        else
            fail("Refusing to replace an unrelated symlink: " .. destination)
        end
    elseif exists(destination) then
        fail(
            "Existing file will not be overwritten: " .. destination
            .. "\nBack it up or move it manually, then retry."
        )
    end

    run({ "ln", "-s", target, destination })
end

local function toml_quote(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\n", "\\n")
    return '"' .. value .. '"'
end

-- ============================================================
-- Directory layout
-- ============================================================

local function create_directories()
    for _, path in ipairs({
        ROOT,
        CONFIG .. "/i3",
        CONFIG .. "/i3status",
        CONFIG .. "/dunst",
        CONFIG .. "/rama",
        BIN,
        SRC,
        LOCAL_BIN,
        HOME .. "/.config/i3",
        HOME .. "/.config/i3status",
        HOME .. "/.config/dunst",
        HOME .. "/.config/rama",
    }) do
        mkdir(path)
    end
end

-- ============================================================
-- Package management
-- ============================================================

local function install_packages()
    local selected = {}

    for _, group in ipairs(enabled_packages) do
        local list = packages[group]

        if not list then
            fail("Unknown package group: " .. group)
        end

        for _, package in ipairs(list) do
            selected[#selected + 1] = package
        end
    end

    log("Updating Debian package lists")
    run({ "sudo", "apt-get", "update" })

    local args = {
        "sudo",
        "apt-get",
        "install",
        "-y",
        "--no-install-recommends",
    }

    for _, package in ipairs(selected) do
        args[#args + 1] = package
    end

    run(args)
end

-- ============================================================
-- Rust toolchain :: rustup + rustc + cargo
-- ============================================================

local function install_rust()
    local cargo_home = HOME .. "/.cargo"
    local cargo_bin = cargo_home .. "/bin"
    local rustup = cargo_bin .. "/rustup"
    local cargo = cargo_bin .. "/cargo"

    -- Install rustup if it is missing.
    if not exists(rustup) then
        log("Installing rustup")

        local installer = os.tmpname()

        run({
            "curl",
            "--proto", "=https",
            "--tlsv1.2",
            "-fsSL",
            "https://sh.rustup.rs",
            "-o", installer,
        })

        local ok, reason, code = os.execute(
            "sh " .. quote(installer) .. " -y --profile minimal"
        )

        os.remove(installer)

        if ok ~= true then
            fail("rustup installation failed: "
                .. tostring(reason) .. " " .. tostring(code))
        end
    end

    if not exists(rustup) or not exists(cargo) then
        fail("rustup or Cargo is missing after installation.")
    end

    -- Ensure Cargo's bin directory is available to child commands.
    local path = cargo_bin .. ":" .. (os.getenv("PATH") or "")

    -- Update rustup itself.
    log("Updating rustup")

    local ok, reason, code = os.execute(
        "PATH=" .. quote(path) .. " "
        .. quote(rustup) .. " self update"
    )

    if ok ~= true then
        fail("rustup update failed: "
            .. tostring(reason) .. " " .. tostring(code))
    end

    -- Install/select the stable toolchain.
    log("Selecting the stable Rust toolchain")

    local function rust_command(...)
        local args = { ... }
        local command = {
            "env",
            "PATH=" .. path,
            rustup,
        }

        for _, value in ipairs(args) do
            command[#command + 1] = value
        end

        run(command)
    end

    rust_command("toolchain", "install", "stable")
    rust_command("default", "stable")

    -- Update rustc, Cargo, and the other installed stable components.
    log("Updating Rust and Cargo")

    rust_command("update", "stable")

    -- Verify the toolchain before attempting the Coqui build.
    run({
        "env",
        "PATH=" .. path,
        cargo,
        "--version",
    })

    run({
        "env",
        "PATH=" .. path,
        cargo_bin .. "/rustc",
        "--version",
    })

    log("Rust toolchain is ready")
end

-- ============================================================
-- Coqui build
-- ============================================================

local function build_coqui()
    log("Preparing Coqui source")

    if not exists(COQUI_DIR .. "/.git") then
        if exists(COQUI_DIR) then
            fail("Coqui source directory exists but is not a Git repository.")
        end

        mkdir(SRC)

        run({
            "git", "clone",
            COQUI_REPO,
            COQUI_DIR,
        })
    end

    log("Fetching Coqui revision")

    run({
        "git", "-C", COQUI_DIR,
        "fetch", "origin", COQUI_REV,
    })

    run({
        "git", "-C", COQUI_DIR,
        "checkout", "--detach", COQUI_REV,
    })

    log("Building Coqui")

    run({
        HOME .. "/.cargo/bin/cargo",
        "build",
        "--release",
        "--manifest-path", COQUI_DIR .. "/Cargo.toml",
    })

    local built = COQUI_DIR .. "/target/release/coqui"

    if not exists(built) then
        fail(
            "Coqui build finished without producing the expected binary:\n"
            .. built
        )
    end

    log("Preparing binary destination")

    mkdir(BIN)

    log("Installing Coqui binary")

    run({
        "install",
        "-m", "0755",
        built,
        COQUI_BIN,
    })

    if not exists(COQUI_BIN) then
        fail("Coqui installation failed: " .. COQUI_BIN)
    end

    log("Coqui installed successfully: " .. COQUI_BIN)
end

-- ============================================================
-- Coqui launcher and power menu
-- ============================================================

local function generate_scripts()
    write_file(BIN .. "/rama-coqui-launch", ([=[
#!/bin/sh
exec st -c floating-terminal -e %q
]=]):format(COQUI_BIN), "0755")

    write_file(BIN .. "/rama-power-menu", [=[
#!/bin/sh

choice=$(
    printf '%s\n' "Shutdown" "Reboot" "Logout" |
        dmenu -i -p "Power:"
)

case "$choice" in
    Shutdown) systemctl poweroff ;;
    Reboot)   systemctl reboot ;;
    Logout)   i3-msg exit ;;
esac
]=], "0755")

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
        if app.optional and not succeeds("command -v " .. quote(app.command)) then
            -- Optional applications are omitted until installed.
        else
            if app.category ~= previous_category then
                lines[#lines + 1] = "[[command]]"
                lines[#lines + 1] = "label = "
                    .. toml_quote("------ " .. app.category)
                lines[#lines + 1] = ""
                previous_category = app.category
            end

            local command = app.command

            if app.terminal then
                command = "st -e " .. command
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
-- i3 configuration generator
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
        "exec --no-startup-id dunst",
        "",
        "# Application launcher",
        "bindsym $mod+space exec --no-startup-id rama-coqui-launch",
        "bindsym $mod+z exec --no-startup-id st",
        "bindsym $mod+Return exec --no-startup-id st",
        "",
        "# Floating terminal",
        'for_window [class="^floating-terminal$"] floating enable, resize set 350 400, move position center',
        "",
    }

    for _, binding in ipairs(keybindings) do
        if binding.command ~= "rama-coqui-launch"
            and binding.command ~= "st" then
            local command = binding.command

            if command == "kill" then
                command = "kill"
            elseif command == "reload" then
                command = "reload"
            end

            lines[#lines + 1] = ("bindsym %s %s"):format(
                binding.key, command
            )
        elseif binding.command == "rama-power-menu" then
            lines[#lines + 1] = "bindsym " .. binding.key
                .. " exec --no-startup-id rama-power-menu"
        end
    end

    lines[#lines + 1] = ""

    for n = 1, 9 do
        lines[#lines + 1] = ("bindsym $mod+%d workspace number %d"):format(n, n)
        lines[#lines + 1] = ("bindsym $mod+Shift+%d move container to workspace number %d"):format(n, n)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "bar {"
    lines[#lines + 1] = "    position top"
    lines[#lines + 1] = "    status_command i3status"
    lines[#lines + 1] = "    colors {"
    lines[#lines + 1] = "        background " .. c.bg
    lines[#lines + 1] = "        statusline " .. c.fg
    lines[#lines + 1] = "        separator " .. c.muted
    lines[#lines + 1] = ("        focused_workspace %s %s %s"):format(c.blue, c.blue, c.bg_dark)
    lines[#lines + 1] = ("        active_workspace %s %s %s"):format(c.bg_alt, c.bg_alt, c.fg)
    lines[#lines + 1] = ("        inactive_workspace %s %s %s"):format(c.bg, c.bg, c.muted)
    lines[#lines + 1] = ("        urgent_workspace %s %s %s"):format(c.danger, c.danger, c.bg_dark)
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

order += "wireless _first_"
order += "battery all"
order += "volume master"
order += "tztime local"

wireless _first_ {
    format_up = "wifi:%%quality %%essid"
    format_down = "wifi:down"
}

battery all {
    format = "bat:%%status %%percentage"
    format_down = "bat:down"
    last_full_capacity = true
}

volume master {
    format = "snd:%%volume"
    format_muted = "snd:muted"
}

tztime local {
    format = "%%m/%%d | %%H:%%M"
}
]=]):format(c.success, c.warning, c.danger))
end

-- ============================================================
-- Dunst configuration
-- ============================================================

local function generate_dunst()
    local c = theme.colors

    write_file(CONFIG .. "/dunst/dunstrc", ([=[
[global]
    width = 300
    height = 100
    origin = top-right
    offset = 10x10
    padding = 8
    horizontal_padding = 8
    frame_width = 2
    frame_color = "%s"
    background = "%s"
    foreground = "%s"
    font = "%s %d"
    timeout = 5

[urgency_low]
    background = "%s"
    foreground = "%s"

[urgency_normal]
    background = "%s"
    foreground = "%s"

[urgency_critical]
    background = "%s"
    foreground = "%s"
    frame_color = "%s"
]=]):format(
        c.accent, c.bg, c.fg,
        theme.font.family, theme.font.size,
        c.bg, c.muted,
        c.bg, c.fg,
        c.danger, c.bg_dark, c.danger
    ))
end

-- ============================================================
-- Managed symlinks
-- ============================================================

local function create_links()
    local links = {
        { CONFIG .. "/i3/config", HOME .. "/.config/i3/config" },
        { CONFIG .. "/i3status/config", HOME .. "/.config/i3status/config" },
        { CONFIG .. "/dunst/dunstrc", HOME .. "/.config/dunst/dunstrc" },
        { CONFIG .. "/rama/coqui_config.toml", HOME .. "/.config/rama/coqui_config.toml" },
    }

    for _, item in ipairs(links) do
        link(item[1], item[2])
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
    generate_dunst()
    create_links()

    log("Configuration applied.")
end

-- ============================================================
-- Validation
-- ============================================================

local function check()
    local failed = false

    for _, command in ipairs({
        "lua5.4",
        "git",
        "cargo",
        "st",
        "i3",
        "i3status",
        "dunst",
    }) do
        if succeeds("command -v " .. quote(command)) then
            print("[OK]      " .. command)
        else
            print("[MISSING] " .. command)
            failed = true
        end
    end

    for _, path in ipairs({
        COQUI_BIN,
        CONFIG .. "/i3/config",
        CONFIG .. "/i3status/config",
        CONFIG .. "/dunst/dunstrc",
        CONFIG .. "/rama/coqui_config.toml",
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
end

-- ============================================================
-- Uninstall
-- ============================================================

local function uninstall()
    local links = {
        { CONFIG .. "/i3/config", HOME .. "/.config/i3/config" },
        { CONFIG .. "/i3status/config", HOME .. "/.config/i3status/config" },
        { CONFIG .. "/dunst/dunstrc", HOME .. "/.config/dunst/dunstrc" },
        { CONFIG .. "/rama/coqui_config.toml", HOME .. "/.config/rama/coqui_config.toml" },
        { BIN .. "/coqui", LOCAL_BIN .. "/coqui" },
        { BIN .. "/rama-coqui-launch", LOCAL_BIN .. "/rama-coqui-launch" },
        { BIN .. "/rama-power-menu", LOCAL_BIN .. "/rama-power-menu" },
    }

    for _, item in ipairs(links) do
        if is_link(item[2]) and read_link(item[2]) == item[1] then
            run({ "rm", item[2] })
        end
    end

    io.write("Remove the Rama installation directory? [y/N] ")
    local answer = io.read("*l") or ""

    if answer:lower() == "y" or answer:lower() == "yes" then
        -- Safety guard: ROOT is a dedicated managed directory.
        if ROOT == HOME .. "/.local/share/rama-oi" then
            run({ "rm", "-rf", "--", ROOT })
        else
            fail("Unexpected installation path; refusing removal.")
        end
    end

    log("Uninstall completed.")
end

-- ============================================================
-- CLI
-- ============================================================

local action = arg[1] or "install"

if action == "install" then
    install_packages()
    install_rust()
    build_coqui()
    apply()
elseif action == "apply" then
    apply()
elseif action == "check" then
    check()
elseif action == "uninstall" then
    uninstall()
else
    io.stderr:write(([=[
Rama-OI %s

Usage:
    lua5.4 install.lua install
    lua5.4 install.lua apply
    lua5.4 install.lua check
    lua5.4 install.lua uninstall
]=]):format(VERSION))
    os.exit(2)
end