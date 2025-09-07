# Documentation

Project documentation for PQCWallet.

## Nonce and WOTS Index

The `nonce()` function of `PQCWallet` is the source of truth for the WOTS signature index. Each successful user operation
consumes one index and increments this nonce, so clients must read `nonce()` before deriving the next WOTS key.
