# et-ghostty

## Brief Overview

Per-host ghostty profiles that run [Eternal Terminal](https://eternalterminal.dev/)
instead of a local shell.

Each profile generates a ghostty config setting `command = et <host>` plus its
own GTK application class, and an `et-ghostty-<name>` wrapper that launches
ghostty with it. Because ghostty runs its configured `command` for *every*
surface it creates, every tab and split inside a profile window is a fresh `et`
session to that host. Because the class differs, a profile window is its own
ghostty process and never merges into your local one.

There is no multiplexer and no daemon in the path — the remote pty talks
straight to a real ghostty. Mouse tracking, bracketed paste, the kitty keyboard
protocol, OSC 52 clipboard, and graphics protocols all negotiate end to end,
because nothing in between is trying to interpret them. This is the main reason
to prefer it over `tmux`/`screen` over ssh, which re-render through their own
terminal emulation and lose the parts they don't understand.

**The trade-off is persistence.** `et` survives network drops, roaming, and
sleep, but only within one client process — it has no reattach. Close the
window, quit ghostty, or reboot, and every remote shell in it dies. If you need
shells to outlive the client, this module is the wrong tool.

## How To Use

```nix
t11s.et-ghostty = {
  enable = true;
  profiles = {
    juicy-j.host = "juicy-j.dab-ling.ts.net";

    bronson = {
      host = "bronson.dab-ling.ts.net";
      settings.theme = "Rose Pine";
    };
  };
};
```

`enable` is **not** implied by defining profiles. Without it nothing is
generated and the wrappers simply won't exist.

Each profile produces an `et-ghostty-<name>` wrapper, exposed as the read-only
`finalPackage` option. Bind it however you launch terminals — for niri:

```nix
"Mod+Shift+Return" = {
  hotkey-overlay.title = "Open a Terminal: juicy-j";
  action.spawn = [
    (lib.getExe config.t11s.et-ghostty.profiles.juicy-j.finalPackage)
  ];
};
```

The wrapper is also added to `home.packages`, so the bare string
`"et-ghostty-juicy-j"` works too. Prefer `finalPackage`: it is an exact store
path rather than a `PATH` lookup, and a typo becomes an eval error instead of a
keybind that silently does nothing.

### Options

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | `bool` | `false` | |
| `desktopEntries.enable` | `bool` | `false` | one launcher entry per profile |
| `package` | `package` | `config.programs.ghostty.package` | ghostty the wrappers launch |
| `etPackage` | `package` | `pkgs.eternal-terminal` | referenced by absolute store path |
| `profiles.<name>.host` | `str` | — | required; passed verbatim to `et` |
| `profiles.<name>.tint` | `nullOr str` | `null` | sugar for `settings.background` |
| `profiles.<name>.class` | `str` | `com.mitchellh.ghostty.<name>` | hyphens folded to `_` |
| `profiles.<name>.settings` | attrs | `{}` | as `programs.ghostty.settings` |
| `profiles.<name>.finalPackage` | `package` | generated | **read-only**; the wrapper |

Enabling this implies `t11s.eternal-terminal.enable`, and requires
`programs.ghostty.enable` — profiles are diffs layered on the base ghostty
config, not replacements for it.

### Launcher entries

On a desktop where terminals come from an application launcher rather than a
keybind (KDE/Plasma, GNOME), turn on desktop entries:

```nix
t11s.et-ghostty.desktopEntries.enable = true;
```

Each profile gets an entry named `Ghostty: <profile>`, using ghostty's own icon.
The setting is global rather than per-profile — if you later want to keep some
profiles out of the launcher, a per-profile override can be added without
breaking existing config.

### Telling remote windows apart

Worth doing, since a remote window is otherwise pixel-identical to a local one
and the failure mode is running the wrong command on the wrong machine. Either
`tint` for a background wash, or `settings.theme` to swap the palette wholesale.

## How It Works

Two ghostty behaviours carry the whole design.

**`command` applies to every surface.** Not just the first window — new tabs,
new splits, and new windows all run it. Note that `-e` and `initial-command` do
*not* work for this: they apply only to the first surface, so `ghostty -e "et
host"` yields a remote first tab and local tabs afterwards.

**A distinct `class` yields a distinct process.** Ghostty's `class` is the GTK
application ID; changing it between invocations creates a separate instance even
under `gtk-single-instance = true`. Without this, launching a profile could hand
off to the already-running local ghostty and quietly open a *local* shell.

### Generated per profile

1. `$XDG_CONFIG_HOME/ghostty/profiles/<name>.conf` — a diff, not a full config.
   Ghostty's CLI-only `config-default-files` defaults to `true`, so
   `--config-file=…` layers on top of your normal config rather than replacing
   it. Rendered with `lib.generators.toKeyValue` using `listsAsDuplicateKeys`,
   since ghostty expresses lists as repeated keys (see `font-family`).
2. A `writeShellScriptBin` wrapper execing
   `ghostty --config-file=<that path>`.

`et` is referenced by absolute store path rather than as a bare `et`. The
wrapper is normally spawned by the compositor, not a shell, so relying on the
inherited `PATH` would invite a "works from a terminal, fails from the keybind"
failure.

### Desktop entries

Generated only when `desktopEntries.enable` is set. Each entry is named after
the profile's `class` — so the file is `com.mitchellh.ghostty.juicy_j.desktop`
— because Wayland shells associate a window with its launcher entry by matching
the reported `app_id` against the desktop file's basename. `StartupWMClass` is
set to the same value for X11 and for shells that use it.

**`DBusActivatable` is explicitly `false`, and that matters.** Ghostty's own
entry sets it to `true`, which works because the package ships a matching
`share/dbus-1/services/com.mitchellh.ghostty.service`. D-Bus activation
resolves the bus name from the desktop file's basename, and there is no service
file for a profile class, so inheriting `true` would leave entries that fail to
launch. This is the concrete form of the warning in ghostty's `class` docs that
changing the class "may break launching Ghostty from `.desktop` files, via DBus
activation, or systemd user services." Launching goes through `Exec` instead,
pointing at the wrapper's absolute store path.

Entries use ghostty's stock icon (`com.mitchellh.ghostty`); profiles are meant
to be told apart by tint or theme. A per-profile `icon` option would slot in
here if that ever stops being enough.

One behavioural note: `gtk-single-instance` is left at ghostty's default of
`detect`, which means *true* unless `TERM_PROGRAM` is set or **any CLI argument
is present**. The wrapper always passes `--config-file=…`, so single-instance is
effectively always off for profiles, on every launch path. Each window is
therefore its own ghostty process and its own `et` session, whether opened from
a launcher entry, a keybind, or a second click on the same entry.

That is usually what you want here, and it has a specific virtue under nix: a
single-instance process inherits the configuration it was launched with, so it
would keep serving stale config after a rebuild until restarted. Per-window
processes pick up the new config immediately. Set
`settings.gtk-single-instance = true` on a profile for one process per host
instead, accepting that trade.

### How a profile inherits the base config

Two ghostty behaviours make the profile a diff rather than a replacement.

**The base config still loads.** `config-default-files` is a CLI-only option
defaulting to `true`, so `ghostty --config-file=<profile>` reads
`$XDG_CONFIG_HOME/ghostty/config` — the one `programs.ghostty` generates — *in
addition to* the profile. Passing `--config-default-files=false` would opt out
and give a hermetic profile; nothing here does.

**The profile wins conflicts, by load order.** From ghostty's `config-file`
docs:

> Configuration files are loaded after the configuration they're defined within
> in the order they're defined. **THIS IS A VERY SUBTLE BUT IMPORTANT POINT.**
> To put it another way: configuration files do not take effect until after the
> entire configuration is loaded.

The referenced file is always later, and later wins. This is why
`settings.theme` in a profile overrides a `theme` set in
`programs.ghostty.settings`.

**Careful with list-valued keys.** The above is last-writer-wins for scalars,
but repeatable keys such as `font-family` *append* instead. A profile setting
`font-family` adds to the base fonts rather than replacing them. Ghostty's
escape hatch is an empty string to reset the list first:

```
font-family = ""
font-family = "My Favorite Font"
```

which from nix means `settings.font-family = [ "" "My Favorite Font" ]`.
Scalars like `theme` and `background` are unaffected.

**You cannot ask ghostty to print a merged profile.** `+show-config` rejects
config overrides — both `+show-config --config-file=…` and
`+show-config --font-size=99` exit 1 with no output. Bare `+show-config` shows
the resolved base config only. Verifying a profile means launching it, or
reasoning from the rules above. `+validate-config --config-file=<profile>` does
work, but only checks the file in isolation.

### Assertions

- **Profile name** must work as an application-ID element: `[A-Za-z0-9_-]`, not
  starting with a digit. Hyphens are sanitized to `_` first, so `juicy-j` is
  fine.
- **Explicit `class` overrides** get the full application-ID check: at least two
  dot-separated elements, none starting with a digit, ≤255 characters.
- **Class uniqueness.** Sanitization is not injective — `a-b` and `a_b` both
  derive `…ghostty.a_b`. Sharing a class means the second launch hands off to
  the first profile's process and opens a window connected to the *wrong host*,
  silently, so this fails at eval time instead.
- **`settings` may not set `command` or `class`.** They are applied after
  `settings`, so a definition there would be discarded without warning.

### Known limitations

- **Shell integration does not apply to remote sessions.** Ghostty's
  `shell-integration = detect` inspects the local command, which is `et`, not a
  shell. Remote tabs get no OSC 133 prompt marks, no jump-to-prompt, and no
  command-finished notifications. Recovering this means installing ghostty's
  integration scripts on the remote host.
- **New tabs start at the remote `$HOME`.** Ghostty's working-directory
  inheritance would hand a remote path to the local `et` process.
- **One ghostty process per window**, each with its own GPU context, because
  passing `--config-file` disables single-instance under `detect` (see Desktop
  entries). Isolates crashes, costs memory. `settings.gtk-single-instance =
  true` trades one for the other.
- **`ctrl+shift+n` inside a profile window opens another remote window,** since
  new windows stay within the process.
