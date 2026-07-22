# Vault backup history fixtures

These immutable fixtures preserve the exact manifest fields written by the
production exporters that introduced each format:

- v2: commit `3e03cb24ece3b07ed32f787ea252821b482b4695`
- v3: commit `a3b5411fac2126eadd962acc9acd9b92f685a892`
- v4: commit `273a4e49fa5b998e1e1ddfa8e5039de0cb8b87a6`

They intentionally omit v5 integrity fields. Compatibility tests must import
these files directly instead of synthesizing an old version from a v5 export.
