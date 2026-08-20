# Part definitions for the raccoon cut-out rig.
#
# Coordinates are in the source 512x512 image. Each part carries the polygon it
# is cut along, the pivot it rotates about, and a feather radius. The cut is
# intersected with the sprite's own alpha, so the outer silhouette stays as
# crisp as the render while the interior cuts are soft enough not to show a
# seam when a joint moves.
#
# Parts that hinge (head, legs, tail, arms) are cut *past* their joint, into
# whatever is drawn on top of them, so a rotation cannot open a hole.

PARTS = [
  # --- behind everything --------------------------------------------------
  dict(name="ear_l", z=0, pivot=(154,140), feather=5, poly=[
    (58,152),(62,96),(74,46),(92,10),(116,-10),(150,-8),(178,26),(196,76),(204,118),(200,152),(180,176),(142,182),(102,176),(72,168)]),

  dict(name="ear_r", z=0, pivot=(390,148), feather=5, poly=[
    (322,34),(352,-12),(412,-12),(444,8),(462,52),(470,108),(462,154),(442,182),(408,190),(376,174),(340,138),(326,84)]),

  dict(name="tail", z=1, pivot=(234,410), feather=8, poly=[
    (246,392),(248,436),(236,462),(214,478),(178,484),(140,478),(108,462),(90,438),(94,416),(118,402),(160,392),(206,388)]),

  # Feet are cut well up into the belly: the hip they swing from has to sit
  # under fur that is drawn on top of them.
  dict(name="leg_l", z=2, pivot=(238,450), feather=7, poly=[
    (252,428),(256,486),(250,504),(228,516),(196,518),(170,510),(158,492),(164,470),(180,448),(210,432)]),

  dict(name="leg_r", z=2, pivot=(400,450), feather=7, poly=[
    (386,428),(414,430),(444,442),(462,466),(464,494),(448,514),(414,518),(388,510),(378,488),(378,450)]),

  # --- the body -----------------------------------------------------------
  # The right edge follows the jacket, not the arm: anything filled in past
  # it lands in the gap between the two and reads as a growth on his hip.
  dict(name="torso", z=3, pivot=(304,424), feather=6, poly=[
    (206,296),(234,278),(270,268),(302,264),(338,268),(372,280),(392,300),(398,338),(390,376),(392,412),(400,452),(390,488),(354,502),(304,506),(256,500),(228,486),(214,454),(206,410),(200,352)]),

  dict(name="arm_r", z=4, pivot=(390,312), feather=6, poly=[
    (372,292),(402,288),(432,304),(452,336),(464,374),(460,406),(442,432),(412,440),(388,426),(378,398),(376,358),(370,326)]),

  # --- the head, and what rides on it -------------------------------------
  dict(name="head", z=5, pivot=(302,298), feather=6, poly=[
    (120,150),(148,128),(190,138),(240,140),(302,136),(358,132),(402,138),(440,156),(466,184),(480,222),(474,258),(454,288),(420,306),(378,318),(326,322),(276,320),(232,308),(194,290),(158,262),(134,222),(120,186)]),

  dict(name="jaw", z=6, pivot=(302,242), feather=5, poly=[
    (244,244),(272,236),(302,234),(334,236),(364,246),(372,268),(362,292),(330,304),(298,308),(264,302),(242,284),(236,262)]),

  dict(name="eye_l", z=7, pivot=(220,186), feather=3, circle=(220,186,41)),
  dict(name="eye_r", z=7, pivot=(340,179), feather=3, circle=(340,179,41)),
  dict(name="pupil_l", z=8, pivot=(222,188), feather=2, circle=(222,188,21)),
  dict(name="pupil_r", z=8, pivot=(340,180), feather=2, circle=(340,180,21)),

  # The brim stops above the eyes: the hat is allowed a few degrees of lag and
  # anything it carries has to be forehead, never eyelid.
  dict(name="hat", z=9, pivot=(284,120), feather=4, poly=[
    (108,162),(118,126),(136,90),(162,56),(196,28),(238,8),(282,0),(320,8),(352,28),(376,58),(396,92),(408,118),(406,132),(380,124),(330,130),(280,136),(228,140),(178,146),(138,156)]),

  # The paw, the forearm and the coin are one rigid piece: he is gripping it,
  # so nothing is gained by hinging them apart, and a great deal of inpainting
  # is avoided by not doing so.
  dict(name="arm_l", z=10, pivot=(226,300), feather=6, poly=[
    (30,236),(36,204),(56,186),(88,182),(120,190),(150,204),(180,222),(210,252),(230,288),(236,330),(228,368),(206,404),(174,428),(128,440),(84,430),(48,400),(24,362),(14,318),(20,272)]),
]
