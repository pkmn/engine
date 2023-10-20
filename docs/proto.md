


### `|move|` (`0x03`)

In Generation IV, the lowest 3 ("slot") bits of `Target` may be `0b000`, in which case the move
either targets a side (in the case of Future Sight, Doom Desire, or Stealth Rock) or there was
`|[notarget]`.

```zig
// TODO: Generation IV test for Future Sight and |[notarget]
```

### `|switch|` (`0x04`)

#### Generation IV

<details><summary>Reason</summary>

| Raw    | Description           |
| ------ | --------------------- |
| `0x00` | None                  |
| `0x01` | `\|[from] Baton Pass` |
| `0x01` | `\|[from] U-turn`     |
</details>

### `|cant|` (`0x05`)


<details><summary>Reason</summary>

| Raw    | Description                | Move? |
| ------ | -------------------------- | ----- |
| `0x00` | `slp`                      | No    |
| `0x01` | `frz`                      | No    |
| `0x02` | `par`                      | No    |
| `0x04` | `flinch`                   | No    |
| `0x05` | `recharge`                 | No    |
| `0x06` | `Attract`                  | No    |
| `0x07` | `ability: Truant`          | No    |
| `0x08` | `Focus Punch\|Focus Punch` | No    |
| `0x09` | `Disable`                  | Yes   |
| `0x0A` | `nopp`                     | Yes   |
| `0x0B` | `move: Taunt`              | Yes   |
| `0x0C` | `move: Imprison`           | Yes   |
| `0x0D` | `move: Heal Block`         | Yes   |
| `0x0E` | `move: Gravity`            | Yes   |
| `0x0F` | `ability: Damp`  TODO      | Yes   |
</details>

```zig
// TODO: Generaiton III/IV support Damp [of]
```