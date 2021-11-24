- Native endianess!
- different (but related) protocol per generation
- if have kwargs change first bit (usually u7, 8th bit is whether kwargs is set) and then second bit is length to indicate the *number* of kwargs
- not guaranteed to be same order as PS, driver code might need to correct
- drop begin of battle message and `|upkeep|`
- **can hp mod be applies at top level, not in engine? just return exact hp always**
  
example docs: https://github.com/couchbase/kv_engine/blob/master/docs/BinaryProtocol.md

```txt
pass
move
switch
team
(shift)

2 bits

2 bits move
3 bits switch

player 1 player 2

continue vs wlt (ended) 2 bits. 2 bits p1 request type 2 bits p2 request type = 6

response 4-5 bits p1, 4-5 p2. team is more complicated… (need u3*6=18 bits each = 40 ttotal)

doubles = 55 55 = 20 bits?
```
