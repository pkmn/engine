#!/usr/bin/env python
from z3 import *

# 100% (255) = 131 (SpikeCannon)
# 85% (215) = 3, 4, 31, 42, 140 (DoubleSlap, CometPunch, FuryAttack, PinMissile, Barage)
# 80% (203) = 154 (Fury Swipes)

total = 10 + 14
state = [BitVec('state%s' % (i + 1), 8) for i in range(total)]

s = Solver()

for i in range(total - 10):
  s.add(state[i + 10] == state[i] * 5 + 1)

# NOTE: first 10 states must all be < 253
s.assert_and_track(ULE(state[0] * 5 + 1, 228), 'Turn 1: P1 Leech Seed hit')
s.assert_and_track(ULE(state[1] * 5 + 1, 228), 'Turn 1: P2 Leech Seed hit')

s.assert_and_track(ULT(state[2] * 5 + 1, 253), 'Turn 2: P1 Confuse Ray hit')
s.assert_and_track(And(ULT(state[3] * 5 + 1, 253), UGE(((state[3] * 5 + 1) & 3) + 2, 3)), 'Turn 2: P2 confusion duration (any)')
s.assert_and_track(ULT(state[4] * 5 + 1, 128), 'Turn 2: P2 avoid confusion self-hit')
s.assert_and_track(ULT(state[5] * 5 + 1, 253), 'Turn 2: P2 Confuse Ray hit')
s.assert_and_track(ULT(state[6] * 5 + 1, 253), 'Turn 2: P1 confusion duration (any')

s.assert_and_track(ULT(state[7] * 5 + 1, 128), 'Turn 3: P1 avoid confusion self-hit')
s.assert_and_track(ULT(state[8] * 5 + 1, 253), 'Turn 3: P1 Metronome crit (any)')
s.assert_and_track(Or(state[9] * 5 + 1 == 154), 'Turn 3: P1 Metronome proc Fury Swipes')
# ---
s.assert_and_track(ULT(RotateLeft(state[10] * 5 + 1, 3), 65), 'Turn 3: P1 Fury Swipes crits')
s.assert_and_track(UGE(RotateRight(state[11] * 5 + 1, 1), 217), 'Turn 3: P1 Fury Swipes damage roll')
s.assert_and_track(ULE(state[12] * 5 + 1, 203), 'Turn 3: P1 Fury Swipes hit')
s.assert_and_track(UGE((state[13] * 5 + 1) & 3, 2), 'Turn 3: P1 Fury Swipes first hitcount')
s.assert_and_track(((state[14] * 5 + 1) & 3) + 2 == 5, 'Turn 3: P1 Fury Swipes max hitcount')
s.assert_and_track(ULT(state[15] * 5 + 1, 128), 'Turn 3: P2 avoid confusion self-hit')
s.assert_and_track(ULT(state[16] * 5 + 1, 255), 'Turn 3: P2 Metronome crit (any)')
s.assert_and_track(Or(state[17] * 5 + 1 == 119), 'Turn 3: P2 Metronome proc MirrorMove')
s.assert_and_track(ULT(state[18] * 5 + 1, 255), 'Turn 3: P2 MirroMove crit (any)')
s.assert_and_track(ULT(RotateLeft(state[19]  * 5 + 1, 3), 65), 'Turn 3: P2 Fury Swipes crits')
s.assert_and_track(UGE(RotateRight(state[20] * 5 + 1, 1), 217), 'Turn 3: P2 Fury Swipes damage roll')
s.assert_and_track(ULE(state[21] * 5 + 1, 203), 'Turn 3: P2 Fury Swipes hit')
s.assert_and_track(UGE((state[22] * 5 + 1) & 3, 2), 'Turn 3: P2 Fury Swipes first hitcount')
s.assert_and_track(((state[23] * 5 + 1) & 3) + 2 == 5, 'Turn 3: P2 Fury Swipes max hitcount')

if (s.check() != unsat):
  m = s.model()

  for i in range(9):
    print(m[state[i]], end = ', ')
  print(m[state[9]])
else:
    print(s.unsat_core())
    exit(1)
