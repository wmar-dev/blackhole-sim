# Render metadata change: backend and precision

Addition to [render-metadata.schema.json](../../001-black-hole-image/contracts/render-metadata.schema.json). Satisfies
FR-006.

A new required top-level object:

```json
"backend": {
  "name": "cpu",
  "precision": "float64"
}
```

| Field | Type | Values |
|-------|------|--------|
| `backend.name` | string | `"cpu"` or `"metal"` |
| `backend.precision` | string | `"float64"` for `cpu`, `"float32"` for `metal` (the precision of ray integration; shading is float64 in both) |

Schema fragment to add under `properties` (and `"backend"` to `required`):

```json
"backend": {
  "type": "object",
  "required": ["name", "precision"],
  "properties": {
    "name": { "enum": ["cpu", "metal"] },
    "precision": { "enum": ["float64", "float32"] }
  }
}
```

Existing fields are unchanged. CPU renders differ from earlier versions only by this added key in the JSON file;
the PNG and EXR are byte-identical (FR-002).
