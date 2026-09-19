# QML checks

Run from this directory:

```sh
/usr/lib/qt6/bin/qmllint Panel.qml Commands.qml
```

`.qmllint.ini` fails on any warning. `.qmlls.ini` provides the same import
path to the QML language server; restart the language server after adding it.

Quickshell supplies `qs` imports at runtime. For static tooling,
`.qmlimports/qs` links to `/usr/share/omarchy/shell`, providing the real `qs.Ui`
and `qs.Commons` components without copying or modifying system files. Update
this symlink if Omarchy is installed elsewhere.

Git tracks the source baseline; use `git diff` to review changes rather than
creating backup copies. Existing `*.bak.*` files are ignored.
