# Swift Package Index discovery

This repository is already a valid Swift Package Manager package:
`Package.swift` exists at the repository root, the repository is public,
and the `v1.0.0` semantic-version Git tag is available.

SwiftPM itself does not require an upload to an external registry. Consumers
can depend directly on:

`https://github.com/pikaid/pikaid-swift.git`

## Optional one-time discovery setup

1. Visit https://swiftpackageindex.com/add-a-package.
2. Submit the complete package URL
   `https://github.com/pikaid/pikaid-swift.git`.
3. After acceptance and indexing, check the resulting Swift Package Index
   package page for build compatibility and release history.

**No recurring uploads, manual version registration, or secret is needed.**
The Swift Package Index watches registered GitHub repositories and
automatically picks up subsequent semantic-version Git tags.

For every new release, keep `Package.swift` valid and create a stable
`vX.Y.Z` tag, then let the existing cross-platform CI test the package.

Official documentation:
- https://swiftpackageindex.com/add-a-package
- https://swiftpackageindex.com/docs/builds
