- Native endianess!
- different (but related) protocol per generation
- if have kwargs change first bit (usually u7, 8th bit is whether kwargs is set) and then second bit is length to indicate the *number* of kwargs
- not guaranteed to be same order as PS, driver code might need to correct
- drop begin of battle message and `|upkeep|`

example docs: https://github.com/couchbase/kv_engine/blob/master/docs/BinaryProtocol.md
