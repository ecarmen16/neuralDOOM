# Installer presentation and recovery checks

The setup window uses a fixed border, a custom multiresolution icon and BYOB(FG) welcome text. Selecting New separate installation hides the existing-install label, selector and browser; the destination is chosen on the following page.

An empty texture ZIP field still means automatic download. Download/import failures terminate installation and emit a dedicated marker so the failure page exposes Texture pack options. Users can then select a publisher ZIP or explicitly skip. Archive verification remains mandatory.

Windows PowerShell 5.1 checks passed: texture wizard (including mode switching and failure recovery navigation), default upgrade, texture importer fixtures, install rollback/copy/uninstall and settings snapshots. Actionlint and PowerShell parsing passed for the cloud workflow/helper. Local Release packaging is the next validation; hosted execution and user gameplay testing remain pending.

Cleanup inspection: bootstrap extraction and texture staging use guarded finally cleanup. The outer embedded payload is removed when setup exits. Download caches, logs and rollback backups are intentionally retained, as is any user-selected original ZIP. No cache purge is added by this change.
