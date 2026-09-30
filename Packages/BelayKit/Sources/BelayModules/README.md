# BelayModules

The optional extras: things Belay can do beside keeping the Mac awake, each one
off until the user installs it from Settings ▸ Modules.

A module is code that ships inside the app. Installing one downloads nothing; it
records the choice in the ledger and lets the module start. That is deliberate:
the App Store forbids fetching executable code, a permission belongs to the
signed app and not to something added later, and a channel that delivers code
is one more thing to defend next to a privileged helper.

This target holds what can be decided without the app: which modules are
installed, what a search matches, which screenshots are due for the Trash,
whether the microphone should be held open, and whether a permission request
names only local sites. The timers, the grants, the microphone, the screen
reading and the views live in `Sources/BelayApp/Modules`.

Writing a module, and the rules one has to keep, are in
[`docs/MODULES.md`](../../../../docs/MODULES.md).
