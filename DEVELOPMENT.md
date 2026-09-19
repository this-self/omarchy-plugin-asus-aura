# Development

## QML linting — no setup required on Omarchy

`.qmllint.ini` loads Omarchy's installed module definitions directly:

- `/usr/share/omarchy/shell/Ui/qmldir`
- `/usr/share/omarchy/shell/Commons/qmldir`

`OverwriteImportTypes` is the settings equivalent of `qmllint -i`, with paths
separated by a colon on Linux. No copied modules, symlinks, generated files,
or sibling directories are needed for linting. All developers using the
standard Omarchy installation use the same paths. For a nonstandard
installation, use `--ignore-settings --max-warnings 0` and two `-i` arguments
pointing to that installation's `qmldir` files.

Run checks from this directory:

```sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint Panel.qml Commands.qml
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("resync.py").read_text())'
git diff --check
```

`.qmllint.ini` fails on any warning. Do not put symlinks anywhere inside the
plugin directory, even in ignored files: the validator scans the filesystem,
not just tracked Git files.

Git tracks the source baseline; use `git diff` to review changes rather than
creating backup copies. Existing `*.bak.*` files are ignored.

## Optional editor support (`qmlls`)

Editor setup is separate from linting. Quickshell supplies the virtual `qs.*`
namespace at runtime, but Qt's language server expects a matching directory
layout: `qs.Ui` becomes `<import-root>/qs/Ui`. Merely putting
`/usr/share/omarchy/shell` in `importPaths` does not provide that mapping.

For editor completion and navigation, you can create a shared mapping in your
user cache and an **untracked, machine-local** `.qmlls.ini`. From the repository
root, on first setup:

```sh
imports="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/qml-imports"
mkdir -p "$imports"
ln -s /usr/share/omarchy/shell "$imports/qs"
printf '[General]\nno-cmake-calls=true\nimportPaths="%s"\n' "$imports" > .qmlls.ini
```

If the link or `.qmlls.ini` already exists, inspect it before running these
commands; preserve any existing editor settings. Restart the QML language
server after setup. The cache mapping can be shared by other Omarchy plugins
and is not tied to the checkout's name or location. Adjust the link target
for a nonstandard Omarchy installation.

`.qmlls.ini` is ignored by Git and is not required for linting, installation,
or runtime. The symlink stays outside the plugin so validation still passes.
The old `.qmlimports/qs` and `../.ifree-kbdbacklight-qmlimports` arrangements
are no longer used. No files under `/usr/share/omarchy/` should be modified.

## Manual smoke test

On supported hardware, with the widget enabled:

1. Open the panel; check that displayed brightness/effect match `asusd`.
2. Check brightness slider, wheel, and right-click off/restore.
3. Try each reported effect and its applicable colour/speed/direction controls.
4. Check keyboard power flags without changing other lighting zones.
5. Run `state`, `set`, `mode`, and panel open/close IPC commands from
   [COMMANDS.md](COMMANDS.md).
6. Try Resync with brightness both On and Off; verify brightness is preserved.
7. Verify the unavailable-service case on a suitable test system.

These checks change lighting settings. Record the original settings and
restore them afterward. Static validation is not a substitute for this test.

## Publication checklist

- Keep the permanent ID `this-self.asus-aura` stable.
- Keep manifest name, version, README, and command reference consistent.
- Review the MIT license and author attribution before publication.
- Replace `OWNER/REPOSITORY` in README installation instructions after choosing
  the public GitHub repository.
- Optionally add a cropped `preview.png` of the panel and embed it in README;
  review the image for private desktop content before committing it.
- Run the checks above and the manual smoke test.
- Commit the intended files, then validate a clean clone (not only the working
  tree). Confirm no tooling symlinks or private files are tracked.
- Publish the repository; optionally tag a release matching `manifest.json`.
- Test installation/removal in a separate test user or machine so the active
  development copy is not replaced or deleted.
- Submit the marketplace's **Submit a Plugin** issue form with the repository
  URL, Hardware category, and allowed tags. Resolve feedback on that issue.

Official instructions:

- [Publishing guide](https://plugins.omarchy.org/publish.html)
- [Marketplace submission requirements](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md)

Marketplace listing is separate from hosting the source. Users can install
from a public Git URL before the listing is approved.
