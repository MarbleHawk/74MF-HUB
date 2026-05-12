# AGENTS.md

## Cursor Cloud specific instructions

### Codebase overview

This repository contains standalone **Roblox Lua (Luau) scripts** designed to run inside the Roblox game client via a script executor. There is no build system, package manager, test framework, or deployable service. The files are extensionless Lua scripts in the repository root.

### Development tools

- **Lua 5.4** (`lua5.4`) — interpreter for syntax checking via `loadfile()`
- **Luacheck 1.2.0** (`luacheck`) — static analysis / linter, installed via `luarocks`
- **Luarocks** — Lua package manager (used to install luacheck)

### Lint

Run luacheck on individual scripts:

```sh
luacheck "ScriptName" --no-color
```

Or lint all scripts at once:

```sh
for f in "Dive Down Money" "Dive Down No Drown" "NPC ESP" "World Fighters" "Homohack" "Decompiler"; do
  luacheck "$f" --no-color
done
```

**Note:** Luacheck will report many "accessing undefined variable" warnings for Roblox engine globals (`game`, `workspace`, `Instance`, `Color3`, `Enum`, `task`, `Vector3`, `UDim2`, etc.). These are false positives — those globals are provided by the Roblox runtime and do not exist in standard Lua. The `74MF HUB` file is heavily obfuscated and cannot be meaningfully linted.

### Syntax checking

```sh
lua5.4 -e "local f, err = loadfile('ScriptName'); if f then print('OK') else print(err) end"
```

### Key caveats

- Scripts **cannot be executed** outside the Roblox game client — they depend on Roblox-specific APIs and a script executor environment.
- The `74MF HUB` file (~622 KB) is obfuscated Lua and is not suitable for linting or syntax checking with standard tools.
- There are no automated tests, no CI/CD, and no build steps.
