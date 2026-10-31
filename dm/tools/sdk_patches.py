# The rewriter's patches of Nintendo SDK module builds (sdk), which several games can ship: dm/tools/patch_nso.py applies those of a module's NSO build ID, whatever the game.
# A patch of a game's own module (main) goes in its profile's patches.py (dm/games/<id>/patches.py). CUTS as described in patch_nso.py ("Registered patches")
# No SDK build this project ships needs a cut. Upstream's entries were keyed to
# other games' sdk builds (their address-region node areas), and this project's one
# game starts with an SDK build that allocates normally. A future game build whose
# sdk needs a cut belongs here, keyed by that build's NSO build ID and checked by
# disassembly first; the form is the one patch_nso.py documents ("Registered
# patches") and dm/tools/tests/test_patches.py enforces.
CUTS = {}
