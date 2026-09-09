# Card faces

One PNG per collectible, 512x512, transparent, rendered by
`tools/render_cards.py` so that every card comes out of the same lighting rig
as the props in `../props`.

    <set_id>_<NN>.png     the card, NN is 1-based and matches the item's place
                          in its set in CV.COLLECTIONS  (beach_01 .. beach_09)
    <set_id>_icon.png     the set's emblem on the shelf

Nothing here is required. `CV.card_tex` returns null for a file that is not
present and every call site falls back to the emoji it used before, which is
what lets the art ship a set at a time instead of in one drop of 150 files.

Drop meshes in a folder and render the lot:

    blender --background --python tools/render_cards.py -- \
        --batch in/beach --out assets/art/cards --material shell
    godot --headless --path . --import
