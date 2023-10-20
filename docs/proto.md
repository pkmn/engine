


### `|move|` (`0x03`)

In Generation IV, the lowest 3 ("slot") bits of `Target` may be `0b000`, in which case the move
either targets a side (in the case of Future Sight, Doom Desire, or Stealth Rock) or there was
`|[notarget]`.

```zig
// TODO: Generation IV test for Future Sight and |[notarget]
```

### `|switch|` (`0x04`)

### Generation IV

<details><summary>Reason</summary>

| Raw    | Description           |
| ------ | --------------------- |
| `0x00` | None                  |
| `0x01` | `\|[from] Baton Pass` |
| `0x01` | `\|[from] U-turn`     |
</details>