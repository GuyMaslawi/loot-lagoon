# Card faces

One PNG per collectible, 512x512, transparent, rendered by
`tools/card_models.py` so that every card comes out of the same lighting rig
as the props in `../props`.

    <set_id>_<NN>.png     the card, NN is 1-based and matches the item's place
                          in its set in CV.COLLECTIONS  (beach_01 .. beach_09)
    <set_id>_icon.png     the set's emblem on the shelf

All fifteen sets are MODELLED IN CODE -- one module per set under
`tools/cardsets/`, primitives only, materials off the palette table in
`tools/render_cards.py`. Fix a card by editing its builder and re-rendering:

    blender --background --python tools/card_models.py -- --set beach
    blender --background --python tools/card_models.py -- --set beach --only 3
    blender --background --python tools/card_models.py -- --all
    godot --headless --path . --import

Iterate cheap with `--res 320 --samples 32` into a scratch dir (`--out`), and
render the whole set per invocation -- each Blender process pays ~70s of
Metal kernel compile before its first frame.

`tools/render_cards.py` still exists for meshes from outside (glb/obj/fbx);
`card_models.py` is the path that needs no outside mesh.

Nothing here is required at runtime. `CV.card_tex` returns null for a file
that is not present and every call site falls back to the emoji it used
before -- which is also what makes a MISNAMED file a silent cosmetic hole, so
`tools/qa_style.tscn` fails the build on any orphan in this directory.
