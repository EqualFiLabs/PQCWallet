# Branching Strategy

This project follows a simplified Git Flow model:

- **main** – stable release branch. Only merge changes via pull requests.
- **develop** – integration branch for completed features.
- **feature/*** – short‑lived branches cut from `develop` for new work. Merge back into `develop` through pull requests.
- **release/*** – prepare production releases from `develop` and merge into both `main` and `develop`.

## Versioning

Releases use [Semantic Versioning](https://semver.org/). The initial release will be **v0.1.0**.

Tag releases on `main` with the corresponding version number.
